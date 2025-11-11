# LLM Gateway API - Elixir HTTP Wrapper for Local LLM Models

This guide shows how to build a production-ready HTTP API gateway that wraps your local LLM (running in Docker) and provides an OpenAI-compatible endpoint that works with LangChain.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Why Elixir for LLM Gateway](#why-elixir-for-llm-gateway)
- [Complete Gateway Implementation](#complete-gateway-implementation)
- [Queue Mechanics & Concurrency Control](#queue-mechanics--concurrency-control)
- [API Endpoint Specification](#api-endpoint-specification)
- [Configuration & Deployment](#configuration--deployment)
- [Client Usage with LangChain](#client-usage-with-langchain)
- [Advanced Features](#advanced-features)

## Architecture Overview

```
┌─────────────┐      HTTP/JSON      ┌──────────────────┐
│  LangChain  │ ─────────────────> │  Elixir Gateway  │
│   Client    │ <───────────────── │   (Phoenix API)  │
└─────────────┘   OpenAI-compatible └──────────────────┘
                                            │
                                    ┌───────┴────────┐
                                    │  Queue System  │
                                    │  (GenStage/    │
                                    │   Broadway)    │
                                    └───────┬────────┘
                                            │
                                     HTTP/gRPC/TCP
                                            │
                                    ┌───────▼────────┐
                                    │  Docker LLM    │
                                    │  (Ollama/vLLM/ │
                                    │   TGI/etc)     │
                                    └────────────────┘
```

**Key Components:**
1. **Phoenix API Server** - HTTP endpoint handling, auth, validation
2. **Queue System** - Request queuing, rate limiting, load balancing
3. **LLM Client** - Communicates with your Docker container
4. **Response Streamer** - SSE (Server-Sent Events) for streaming responses

## Why Elixir for LLM Gateway

✅ **Concurrency** - Handle thousands of simultaneous connections with lightweight processes
✅ **Queue Mechanics** - Built-in GenStage/Broadway for backpressure and rate limiting
✅ **Fault Tolerance** - Supervisor trees for automatic recovery
✅ **Hot Code Swapping** - Update without downtime
✅ **Low Latency** - Ideal for real-time streaming responses
✅ **OTP Platform** - Battle-tested distributed systems framework

## Complete Gateway Implementation

### Project Setup

```bash
mix phx.new llm_gateway --no-ecto --no-html --no-assets
cd llm_gateway
```

Add dependencies to `mix.exs`:

```elixir
defp deps do
  [
    {:phoenix, "~> 1.7.0"},
    {:plug_cowboy, "~> 2.5"},
    {:jason, "~> 1.4"},
    {:finch, "~> 0.16"},
    {:gen_stage, "~> 1.2"},
    {:broadway, "~> 1.0"},
    {:corsica, "~> 2.0"},
    {:joken, "~> 2.6"},  # For JWT auth
    {:telemetry, "~> 1.2"},
    {:telemetry_metrics, "~> 1.0"}
  ]
end
```

### 1. API Router

```elixir
# lib/llm_gateway_web/router.ex
defmodule LLMGatewayWeb.Router do
  use Phoenix.Router

  import Plug.Conn

  pipeline :api do
    plug :accepts, ["json"]
    plug LLMGatewayWeb.Plugs.APIAuth
    plug LLMGatewayWeb.Plugs.RateLimit
    plug Corsica, origins: "*", allow_headers: ["authorization", "content-type"]
  end

  scope "/v1", LLMGatewayWeb do
    pipe_through :api

    # OpenAI-compatible endpoints
    post "/chat/completions", ChatController, :create
    get "/models", ModelsController, :index
    get "/models/:model_id", ModelsController, :show

    # Health check
    get "/health", HealthController, :check
  end
end
```

### 2. Authentication Plug

```elixir
# lib/llm_gateway_web/plugs/api_auth.ex
defmodule LLMGatewayWeb.Plugs.APIAuth do
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    # Skip auth for health check
    if conn.request_path == "/v1/health" do
      conn
    else
      verify_api_key(conn)
    end
  end

  defp verify_api_key(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> api_key] ->
        if valid_api_key?(api_key) do
          assign(conn, :api_key, api_key)
        else
          unauthorized(conn)
        end

      _ ->
        unauthorized(conn)
    end
  end

  defp valid_api_key?(api_key) do
    # Check against your API key store (ETS, Redis, Database)
    api_keys = Application.get_env(:llm_gateway, :api_keys, [])

    Enum.any?(api_keys, fn {key, _metadata} ->
      Plug.Crypto.secure_compare(key, api_key)
    end)
  end

  defp unauthorized(conn) do
    conn
    |> put_status(401)
    |> Phoenix.Controller.json(%{
      error: %{
        message: "Invalid API key",
        type: "invalid_request_error",
        code: "invalid_api_key"
      }
    })
    |> halt()
  end
end
```

### 3. Rate Limiting Plug

```elixir
# lib/llm_gateway_web/plugs/rate_limit.ex
defmodule LLMGatewayWeb.Plugs.RateLimit do
  import Plug.Conn

  @ets_table :rate_limits

  def init(opts), do: opts

  def call(conn, _opts) do
    api_key = conn.assigns[:api_key]

    if api_key && rate_limited?(api_key) do
      conn
      |> put_status(429)
      |> Phoenix.Controller.json(%{
        error: %{
          message: "Rate limit exceeded",
          type: "rate_limit_error"
        }
      })
      |> halt()
    else
      conn
    end
  end

  defp rate_limited?(api_key) do
    now = System.system_time(:second)
    window = 60  # 1 minute window
    limit = 60   # 60 requests per minute

    key = {api_key, div(now, window)}

    case :ets.update_counter(@ets_table, key, {2, 1}, {key, 0}) do
      count when count > limit -> true
      _count -> false
    end
  end
end
```

### 4. Chat Controller (OpenAI-Compatible)

```elixir
# lib/llm_gateway_web/controllers/chat_controller.ex
defmodule LLMGatewayWeb.ChatController do
  use Phoenix.Controller
  require Logger

  alias LLMGateway.LLMQueue
  alias LLMGateway.LLMClient

  @doc """
  POST /v1/chat/completions

  OpenAI-compatible chat completions endpoint.
  Supports both streaming and non-streaming requests.
  """
  def create(conn, params) do
    with {:ok, validated} <- validate_params(params),
         {:ok, request_id} <- generate_request_id() do

      if validated.stream do
        stream_response(conn, validated, request_id)
      else
        sync_response(conn, validated, request_id)
      end
    else
      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{
          error: %{
            message: reason,
            type: "invalid_request_error"
          }
        })
    end
  end

  defp validate_params(params) do
    required = ["model", "messages"]

    if Enum.all?(required, &Map.has_key?(params, &1)) do
      {:ok, %{
        model: params["model"],
        messages: params["messages"],
        temperature: params["temperature"] || 0.7,
        max_tokens: params["max_tokens"] || 2048,
        stream: params["stream"] || false,
        stop: params["stop"],
        top_p: params["top_p"] || 1.0
      }}
    else
      {:error, "Missing required parameters: #{Enum.join(required, ", ")}"}
    end
  end

  defp generate_request_id do
    {:ok, "chatcmpl-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)}
  end

  # Non-streaming response
  defp sync_response(conn, params, request_id) do
    Logger.info("Sync request #{request_id} for model #{params.model}")

    # Enqueue request and wait for response
    case LLMQueue.enqueue_and_wait(params, timeout: 120_000) do
      {:ok, response_text, usage} ->
        conn
        |> put_status(200)
        |> json(%{
          id: request_id,
          object: "chat.completion",
          created: System.system_time(:second),
          model: params.model,
          choices: [
            %{
              index: 0,
              message: %{
                role: "assistant",
                content: response_text
              },
              finish_reason: "stop"
            }
          ],
          usage: usage
        })

      {:error, :timeout} ->
        conn
        |> put_status(504)
        |> json(%{error: %{message: "Request timeout", type: "timeout_error"}})

      {:error, reason} ->
        Logger.error("LLM error: #{inspect(reason)}")
        conn
        |> put_status(500)
        |> json(%{error: %{message: "Internal server error", type: "server_error"}})
    end
  end

  # Streaming response (SSE)
  defp stream_response(conn, params, request_id) do
    Logger.info("Stream request #{request_id} for model #{params.model}")

    conn
    |> put_resp_content_type("text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("connection", "keep-alive")
    |> send_chunked(200)
    |> stream_chunks(params, request_id)
  end

  defp stream_chunks(conn, params, request_id) do
    # Enqueue streaming request
    {:ok, stream} = LLMQueue.enqueue_stream(params)

    try do
      Enum.reduce_while(stream, conn, fn chunk, conn ->
        case chunk do
          {:data, content} ->
            data = %{
              id: request_id,
              object: "chat.completion.chunk",
              created: System.system_time(:second),
              model: params.model,
              choices: [
                %{
                  index: 0,
                  delta: %{content: content},
                  finish_reason: nil
                }
              ]
            }

            case send_sse_chunk(conn, data) do
              {:ok, conn} -> {:cont, conn}
              {:error, _} -> {:halt, conn}
            end

          {:done, usage} ->
            # Send final chunk
            final = %{
              id: request_id,
              object: "chat.completion.chunk",
              created: System.system_time(:second),
              model: params.model,
              choices: [
                %{
                  index: 0,
                  delta: %{},
                  finish_reason: "stop"
                }
              ],
              usage: usage
            }

            send_sse_chunk(conn, final)
            send_sse_done(conn)
            {:halt, conn}

          {:error, reason} ->
            Logger.error("Stream error: #{inspect(reason)}")
            {:halt, conn}
        end
      end)
    rescue
      e ->
        Logger.error("Stream exception: #{inspect(e)}")
        conn
    end
  end

  defp send_sse_chunk(conn, data) do
    json_data = Jason.encode!(data)
    chunk(conn, "data: #{json_data}\n\n")
  end

  defp send_sse_done(conn) do
    chunk(conn, "data: [DONE]\n\n")
  end
end
```

### 5. Queue System with GenStage

```elixir
# lib/llm_gateway/llm_queue.ex
defmodule LLMGateway.LLMQueue do
  @moduledoc """
  Queue system for LLM requests with backpressure control.
  Uses GenStage to handle concurrent request processing.
  """

  use GenStage
  require Logger

  @max_concurrent_requests 4  # Adjust based on your GPU/model capacity

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enqueue a request and wait for response (sync).
  """
  def enqueue_and_wait(params, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 120_000)

    task = Task.async(fn ->
      request_ref = make_ref()
      GenStage.call(__MODULE__, {:enqueue, params, self(), request_ref}, timeout)

      receive do
        {:response, ^request_ref, result} -> result
      after
        timeout -> {:error, :timeout}
      end
    end)

    Task.await(task, timeout)
  end

  @doc """
  Enqueue a streaming request.
  Returns a stream that emits chunks.
  """
  def enqueue_stream(params) do
    {:ok, pid} = LLMGateway.StreamProducer.start_link(params)
    {:ok, GenStage.stream([{pid, []}])}
  end

  ## GenStage Callbacks

  @impl true
  def init(_opts) do
    {:producer, {:queue.new(), 0}, dispatcher: GenStage.DemandDispatcher}
  end

  @impl true
  def handle_call({:enqueue, params, caller, ref}, _from, {queue, pending_demand}) do
    queue = :queue.in({params, caller, ref}, queue)
    {:reply, :ok, [], {queue, pending_demand}}
  end

  @impl true
  def handle_demand(incoming_demand, {queue, pending_demand}) do
    dispatch_events(queue, incoming_demand + pending_demand, [])
  end

  defp dispatch_events(queue, 0, events) do
    {:noreply, Enum.reverse(events), {queue, 0}}
  end

  defp dispatch_events(queue, demand, events) do
    case :queue.out(queue) do
      {{:value, item}, queue} ->
        dispatch_events(queue, demand - 1, [item | events])

      {:empty, queue} ->
        {:noreply, Enum.reverse(events), {queue, demand}}
    end
  end
end
```

### 6. Queue Consumer (Worker)

```elixir
# lib/llm_gateway/llm_consumer.ex
defmodule LLMGateway.LLMConsumer do
  @moduledoc """
  Consumer that processes LLM requests from the queue.
  """

  use GenStage
  require Logger

  alias LLMGateway.LLMClient

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    {:consumer, %{}, subscribe_to: [{LLMGateway.LLMQueue, []}]}
  end

  @impl true
  def handle_events(events, _from, state) do
    for {params, caller, ref} <- events do
      Task.start(fn ->
        result = process_request(params)
        send(caller, {:response, ref, result})
      end)
    end

    {:noreply, [], state}
  end

  defp process_request(params) do
    start_time = System.monotonic_time(:millisecond)

    result = LLMClient.generate(params)

    duration = System.monotonic_time(:millisecond) - start_time
    Logger.info("Request completed in #{duration}ms")

    result
  end
end
```

### 7. LLM Client (Connects to Docker Container)

```elixir
# lib/llm_gateway/llm_client.ex
defmodule LLMGateway.LLMClient do
  @moduledoc """
  Client for communicating with LLM running in Docker.
  Supports multiple backend types: Ollama, vLLM, TGI, etc.
  """

  require Logger

  @doc """
  Generate completion from LLM.
  """
  def generate(params) do
    backend = Application.get_env(:llm_gateway, :llm_backend, :ollama)

    case backend do
      :ollama -> generate_ollama(params)
      :vllm -> generate_vllm(params)
      :tgi -> generate_tgi(params)
      :custom -> generate_custom(params)
    end
  end

  ## Ollama Backend

  defp generate_ollama(params) do
    url = get_backend_url() <> "/api/chat"

    payload = %{
      model: params.model,
      messages: params.messages,
      stream: false,
      options: %{
        temperature: params.temperature,
        num_predict: params.max_tokens,
        top_p: params.top_p,
        stop: params.stop
      }
    }

    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(payload)

    case Finch.build(:post, url, headers, body)
         |> Finch.request(LLMGateway.Finch, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"message" => %{"content" => content}}} ->
            usage = extract_usage_ollama(response_body)
            {:ok, content, usage}

          {:error, _} = error ->
            Logger.error("Failed to decode Ollama response: #{inspect(error)}")
            {:error, :decode_error}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("Ollama returned #{status}: #{body}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Ollama request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  ## vLLM Backend

  defp generate_vllm(params) do
    url = get_backend_url() <> "/v1/chat/completions"

    payload = %{
      model: params.model,
      messages: params.messages,
      temperature: params.temperature,
      max_tokens: params.max_tokens,
      top_p: params.top_p,
      stop: params.stop
    }

    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(payload)

    case Finch.build(:post, url, headers, body)
         |> Finch.request(LLMGateway.Finch, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _], "usage" => usage}} ->
            {:ok, content, format_usage(usage)}

          {:error, _} = error ->
            {:error, :decode_error}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Text Generation Inference (TGI) Backend

  defp generate_tgi(params) do
    url = get_backend_url() <> "/generate"

    # Convert chat messages to prompt
    prompt = messages_to_prompt(params.messages)

    payload = %{
      inputs: prompt,
      parameters: %{
        temperature: params.temperature,
        max_new_tokens: params.max_tokens,
        top_p: params.top_p,
        stop: params.stop || []
      }
    }

    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(payload)

    case Finch.build(:post, url, headers, body)
         |> Finch.request(LLMGateway.Finch, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"generated_text" => content, "details" => details}} ->
            usage = extract_usage_tgi(details)
            {:ok, String.trim(content), usage}

          {:error, _} ->
            {:error, :decode_error}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Custom Backend (Your implementation)

  defp generate_custom(params) do
    # Implement your custom protocol here
    # This could be gRPC, raw TCP, or any other protocol

    url = get_backend_url()
    # ... your custom implementation
  end

  ## Helpers

  defp get_backend_url do
    Application.get_env(:llm_gateway, :llm_backend_url, "http://localhost:11434")
  end

  defp messages_to_prompt(messages) do
    Enum.map_join(messages, "\n", fn msg ->
      role = String.capitalize(msg["role"])
      "#{role}: #{msg["content"]}"
    end)
  end

  defp extract_usage_ollama(_response) do
    # Ollama doesn't return usage in the same format
    # You may need to parse eval_count, prompt_eval_count from response
    %{
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0
    }
  end

  defp extract_usage_tgi(details) do
    %{
      prompt_tokens: details["prefill"] || 0,
      completion_tokens: details["generated_tokens"] || 0,
      total_tokens: (details["prefill"] || 0) + (details["generated_tokens"] || 0)
    }
  end

  defp format_usage(usage) do
    %{
      prompt_tokens: usage["prompt_tokens"] || 0,
      completion_tokens: usage["completion_tokens"] || 0,
      total_tokens: usage["total_tokens"] || 0
    }
  end
end
```

### 8. Stream Producer (for SSE)

```elixir
# lib/llm_gateway/stream_producer.ex
defmodule LLMGateway.StreamProducer do
  use GenStage
  require Logger

  alias LLMGateway.LLMClient

  def start_link(params) do
    GenStage.start_link(__MODULE__, params)
  end

  @impl true
  def init(params) do
    {:producer, %{params: params, buffer: []}}
  end

  @impl true
  def handle_demand(demand, state) when demand > 0 do
    # Start streaming from LLM
    if state.buffer == [] do
      spawn_link(fn -> stream_from_llm(self(), state.params) end)
    end

    {:noreply, [], state}
  end

  @impl true
  def handle_info({:chunk, content}, state) do
    {:noreply, [{:data, content}], state}
  end

  def handle_info({:done, usage}, state) do
    {:noreply, [{:done, usage}], state}
  end

  def handle_info({:error, reason}, state) do
    {:noreply, [{:error, reason}], state}
  end

  defp stream_from_llm(producer_pid, params) do
    # Stream from LLM backend
    backend = Application.get_env(:llm_gateway, :llm_backend, :ollama)
    url = Application.get_env(:llm_gateway, :llm_backend_url, "http://localhost:11434")

    case backend do
      :ollama ->
        stream_ollama(producer_pid, url <> "/api/chat", params)

      :vllm ->
        stream_vllm(producer_pid, url <> "/v1/chat/completions", params)

      _ ->
        send(producer_pid, {:error, :streaming_not_supported})
    end
  end

  defp stream_ollama(producer_pid, url, params) do
    payload = %{
      model: params.model,
      messages: params.messages,
      stream: true,
      options: %{
        temperature: params.temperature,
        num_predict: params.max_tokens
      }
    }

    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(payload)

    request = Finch.build(:post, url, headers, body)

    Finch.stream(request, LLMGateway.Finch, nil, fn
      {:status, _status}, acc -> acc
      {:headers, _headers}, acc -> acc

      {:data, data}, acc ->
        # Parse SSE chunks
        String.split(data, "\n", trim: true)
        |> Enum.each(fn line ->
          case Jason.decode(line) do
            {:ok, %{"message" => %{"content" => content}}} when content != "" ->
              send(producer_pid, {:chunk, content})

            {:ok, %{"done" => true}} ->
              send(producer_pid, {:done, %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}})

            _ ->
              :ok
          end
        end)

        acc
    end)
  end

  defp stream_vllm(producer_pid, url, params) do
    payload = %{
      model: params.model,
      messages: params.messages,
      temperature: params.temperature,
      max_tokens: params.max_tokens,
      stream: true
    }

    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(payload)

    request = Finch.build(:post, url, headers, body)

    Finch.stream(request, LLMGateway.Finch, nil, fn
      {:status, _}, acc -> acc
      {:headers, _}, acc -> acc

      {:data, data}, acc ->
        String.split(data, "\n", trim: true)
        |> Enum.each(fn line ->
          case String.trim_leading(line, "data: ") do
            "[DONE]" ->
              send(producer_pid, {:done, %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}})

            json_str ->
              case Jason.decode(json_str) do
                {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}} when content != "" ->
                  send(producer_pid, {:chunk, content})

                _ ->
                  :ok
              end
          end
        end)

        acc
    end)
  end
end
```

### 9. Application Supervisor

```elixir
# lib/llm_gateway/application.ex
defmodule LLMGateway.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Create ETS table for rate limiting
    :ets.new(:rate_limits, [:set, :public, :named_table])

    children = [
      # HTTP client pool
      {Finch, name: LLMGateway.Finch, pools: %{
        default: [size: 32, count: 4]
      }},

      # Queue system
      LLMGateway.LLMQueue,

      # Start multiple consumers (workers)
      Enum.map(1..4, fn i ->
        Supervisor.child_spec(
          {LLMGateway.LLMConsumer, []},
          id: {LLMGateway.LLMConsumer, i}
        )
      end),

      # Phoenix endpoint
      LLMGatewayWeb.Endpoint
    ]
    |> List.flatten()

    opts = [strategy: :one_for_one, name: LLMGateway.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### 10. Configuration

```elixir
# config/config.exs
import Config

config :llm_gateway,
  # LLM Backend configuration
  llm_backend: :ollama,  # :ollama, :vllm, :tgi, :custom
  llm_backend_url: System.get_env("LLM_BACKEND_URL", "http://localhost:11434"),

  # API Keys (load from env or secure store)
  api_keys: [
    {"sk-test-key-1", %{user: "user1", rate_limit: 60}},
    {"sk-test-key-2", %{user: "user2", rate_limit: 120}}
  ],

  # Queue settings
  max_concurrent_requests: String.to_integer(System.get_env("MAX_CONCURRENT", "4")),
  request_timeout: 120_000

config :llm_gateway, LLMGatewayWeb.Endpoint,
  url: [host: "localhost"],
  http: [port: 4000],
  server: true,
  secret_key_base: "your-secret-key-base"

# Production config
import_config "#{config_env()}.exs"
```

```elixir
# config/prod.exs
import Config

config :llm_gateway,
  llm_backend: String.to_atom(System.get_env("LLM_BACKEND", "ollama")),
  llm_backend_url: System.get_env("LLM_BACKEND_URL")!,
  api_keys: load_api_keys_from_env()

defp load_api_keys_from_env do
  # Load from environment or secret management system
  case System.get_env("API_KEYS_JSON") do
    nil -> []
    json ->
      Jason.decode!(json)
      |> Enum.map(fn {key, meta} -> {key, Map.new(meta)} end)
  end
end
```

## API Endpoint Specification

### Authentication

All requests must include an API key in the Authorization header:

```http
Authorization: Bearer sk-your-api-key-here
```

### Chat Completions (Non-Streaming)

**Request:**
```http
POST /v1/chat/completions
Content-Type: application/json

{
  "model": "llama3.2:latest",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello!"}
  ],
  "temperature": 0.7,
  "max_tokens": 2048
}
```

**Response:**
```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1699999999,
  "model": "llama3.2:latest",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! How can I help you today?"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 20,
    "completion_tokens": 10,
    "total_tokens": 30
  }
}
```

### Chat Completions (Streaming)

**Request:**
```http
POST /v1/chat/completions
Content-Type: application/json

{
  "model": "llama3.2:latest",
  "messages": [...],
  "stream": true
}
```

**Response (SSE):**
```
data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1699999999,"model":"llama3.2:latest","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1699999999,"model":"llama3.2:latest","choices":[{"index":0,"delta":{"content":"!"},"finish_reason":null}]}

data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1699999999,"model":"llama3.2:latest","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":20,"completion_tokens":10,"total_tokens":30}}

data: [DONE]
```

## Configuration & Deployment

### Docker Compose Setup

```yaml
# docker-compose.yml
version: '3.8'

services:
  # Ollama LLM Backend
  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    environment:
      - OLLAMA_NUM_PARALLEL=4
      - OLLAMA_MAX_LOADED_MODELS=2
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]

  # Elixir Gateway
  llm_gateway:
    build: .
    ports:
      - "4000:4000"
    environment:
      - LLM_BACKEND=ollama
      - LLM_BACKEND_URL=http://ollama:11434
      - MAX_CONCURRENT=4
      - API_KEYS_JSON={"sk-test":"{"user":"test","rate_limit":60}}"}
    depends_on:
      - ollama
    restart: unless-stopped

volumes:
  ollama_data:
```

### Dockerfile

```dockerfile
# Dockerfile
FROM elixir:1.15-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache build-base git

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application code
COPY . .

# Compile and build release
RUN mix compile
RUN mix release

# Production image
FROM alpine:3.18

RUN apk add --no-cache openssl ncurses-libs libstdc++

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/llm_gateway ./

ENV HOME=/app
ENV MIX_ENV=prod

CMD ["bin/llm_gateway", "start"]
```

## Client Usage with LangChain

### Using with GettextTranslator

```elixir
# config/config.exs
config :gettext_translator, GettextTranslator,
  endpoint: LangChain.ChatModels.ChatOpenAI,
  endpoint_model: "llama3.2:latest",
  endpoint_temperature: 0,
  endpoint_config: %{
    "openai_key" => "sk-your-api-key",
    "openai_endpoint" => "http://your-gateway.com:4000/v1/chat/completions"
  },
  persona: "Professional translator",
  style: "Casual",
  ignored_languages: ["en"]
```

### Using with LangChain Directly

```elixir
alias LangChain.ChatModels.ChatOpenAI
alias LangChain.Chains.LLMChain
alias LangChain.Message

# Configure to use your gateway
Application.put_env(:langchain, :openai_key, "sk-your-api-key")
Application.put_env(:langchain, :openai_endpoint, "http://your-gateway.com:4000/v1/chat/completions")

# Create LLM
{:ok, llm} = ChatOpenAI.new(%{
  model: "llama3.2:latest",
  temperature: 0.7
})

# Create chain
{:ok, chain} = LLMChain.new(%{llm: llm})
|> LLMChain.add_message(Message.new_user!("Translate 'hello' to Spanish"))
|> LLMChain.run()

# Get response
response = LangChain.Message.ContentPart.parts_to_string(chain.last_message.content)
```

## Advanced Features

### 1. Model Management

```elixir
# lib/llm_gateway_web/controllers/models_controller.ex
defmodule LLMGatewayWeb.ModelsController do
  use Phoenix.Controller

  def index(conn, _params) do
    models = LLMGateway.ModelRegistry.list_models()

    json(conn, %{
      object: "list",
      data: Enum.map(models, &format_model/1)
    })
  end

  defp format_model(model) do
    %{
      id: model.name,
      object: "model",
      created: model.created_at,
      owned_by: "local",
      capabilities: model.capabilities
    }
  end
end
```

### 2. Request Prioritization

```elixir
# Add priority to queue
def enqueue_with_priority(params, priority \\ :normal) do
  GenStage.call(__MODULE__, {:enqueue, params, priority, self(), make_ref()})
end

# In init, use priority queue
{:producer, PriorityQueue.new(), dispatcher: GenStage.DemandDispatcher}
```

### 3. Metrics & Monitoring

```elixir
# lib/llm_gateway/telemetry.ex
defmodule LLMGateway.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Queue metrics
      last_value("llm_gateway.queue.length"),
      last_value("llm_gateway.queue.pending_demand"),

      # Request metrics
      counter("llm_gateway.request.count"),
      distribution("llm_gateway.request.duration", unit: {:native, :millisecond}),

      # Error metrics
      counter("llm_gateway.error.count")
    ]
  end

  defp periodic_measurements do
    []
  end
end
```

### 4. Caching Layer

```elixir
# lib/llm_gateway/cache.ex
defmodule LLMGateway.Cache do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def put(key, value, ttl \\ 3600) do
    GenServer.cast(__MODULE__, {:put, key, value, ttl})
  end

  def init(_opts) do
    :ets.new(:llm_cache, [:set, :public, :named_table])
    {:ok, %{}}
  end

  # ... implementation
end
```

## Summary

This Elixir-based LLM gateway provides:

✅ **OpenAI-compatible API** - Works seamlessly with LangChain
✅ **Queue mechanics** - GenStage-based backpressure control
✅ **Concurrency control** - Prevents overloading your GPU
✅ **Rate limiting** - Per-API-key rate limits
✅ **Streaming support** - SSE for real-time responses
✅ **Multiple backends** - Ollama, vLLM, TGI support
✅ **Authentication** - API key-based auth
✅ **Fault tolerance** - Supervisor trees for reliability
✅ **Metrics ready** - Telemetry integration

Deploy it alongside your Docker LLM container and expose it to your users with API keys!
