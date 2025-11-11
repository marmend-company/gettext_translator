# Custom LLM Endpoint Guide

This guide explains how to integrate custom LLM endpoints with GettextTranslator using LangChain 0.4.0.

## Table of Contents

- [Overview](#overview)
- [Supported Models](#supported-models)
- [Response Format Requirements](#response-format-requirements)
  - [Synchronous Response](#synchronous-non-streaming-response)
  - [Streaming Response](#streaming-response)
  - [Error Response](#error-response)
- [Custom Adapter Implementation](#custom-adapter-implementation)
- [Configuration](#configuration)
- [Testing](#testing-your-custom-endpoint)
- [Common Issues](#common-issues)
- [Examples](#examples)

## Overview

GettextTranslator uses LangChain to communicate with LLM providers. As of version 0.5.0, the library uses LangChain 0.4.0, which introduced breaking changes in how messages are structured.

**Key Change in LangChain 0.4.0:**
- Message `content` is now a **list of ContentPart structs** instead of plain strings
- All custom endpoints must return responses in this format

## Supported Models

LangChain 0.4.0 officially supports:

| Provider | Module | Status |
|----------|--------|--------|
| OpenAI | `LangChain.ChatModels.ChatOpenAI` | ✅ Fully Supported |
| Anthropic | `LangChain.ChatModels.ChatAnthropic` | ✅ Fully Supported |
| Google Gemini | `LangChain.ChatModels.ChatGoogleAI` | ✅ Fully Supported |
| Google Vertex AI | `LangChain.ChatModels.ChatVertexAI` | ✅ Fully Supported |
| Ollama | `LangChain.ChatModels.ChatOllamaAI` | ⚠️ May not work |
| Others | Custom implementation | ⚠️ Requires custom adapter |

**Important:** If you're using Ollama or other unsupported models, they may not function correctly with LangChain 0.4.0. Consider:
- Using GettextTranslator 0.4.5 (with LangChain 0.3.3)
- Switching to a supported provider
- Implementing a custom adapter (see below)

## Response Format Requirements

### Synchronous (Non-Streaming) Response

Your LLM endpoint must return a tuple `{:ok, updated_chain}` where the chain contains the response message.

**Required Structure:**

```elixir
{:ok, %LangChain.Chains.LLMChain{
  last_message: %LangChain.Message{
    role: :assistant,
    content: [
      %LangChain.Message.ContentPart{
        type: :text,
        content: "Translated text here"
      }
    ],
    status: :complete,
    index: 0
  },
  messages: [
    # All messages in the conversation
  ]
}}
```

**Critical Requirements:**

1. **Content as List**: `content` MUST be a list of `ContentPart` structs
   ```elixir
   # ✅ CORRECT
   content: [%ContentPart{type: :text, content: "text"}]

   # ❌ WRONG
   content: "text"
   ```

2. **ContentPart Structure**: Each part must have `type` and `content`
   ```elixir
   %LangChain.Message.ContentPart{
     type: :text,        # Required: :text, :image, :tool_call, etc.
     content: "string"   # Required: the actual content
   }
   ```

3. **Message Fields**:
   - `role`: Must be `:assistant` for LLM responses
   - `status`: Should be `:complete` when done
   - `content`: List of ContentPart structs (never a string)

### Streaming Response

For streaming responses, emit deltas via callbacks.

**Delta Structure:**

```elixir
# Each delta emitted
%LangChain.MessageDelta{
  role: :assistant,
  content: [
    %LangChain.Message.ContentPart{
      type: :text,
      content: "Partial text chunk"
    }
  ],
  status: :incomplete  # or :complete for the final delta
}
```

**Streaming Requirements:**

1. The `on_llm_new_delta` callback receives a **list of deltas**:
   ```elixir
   def handle_delta(deltas) when is_list(deltas) do
     # Process list of MessageDelta structs
   end
   ```

2. Merge deltas using `LLMChain.merge_deltas/2`:
   ```elixir
   updated_chain = LLMChain.merge_deltas(current_chain, deltas)
   ```

3. Access merged content via `MessageDelta.merged_content`:
   ```elixir
   text = updated_chain.delta.merged_content
   ```

4. Final delta must have `status: :complete`

### Error Response

On error, return a three-element tuple:

```elixir
{:error, updated_chain, reason}
```

**Components:**
- `updated_chain`: The chain state at the time of error (can be `nil`)
- `reason`: Error description (string, atom, or structured error)

**Example:**

```elixir
{:error, chain, "API rate limit exceeded"}
```

GettextTranslator handles errors gracefully:
- Logs the error with context
- Returns an empty translation `{:ok, ""}`
- Allows the translation process to continue

## Custom Adapter Implementation

### Minimal Adapter Example

```elixir
defmodule MyApp.CustomLLMAdapter do
  @moduledoc """
  Custom LLM adapter for GettextTranslator using LangChain 0.4.0.
  """

  use LangChain.ChatModels.ChatModel

  alias LangChain.Message
  alias LangChain.Message.ContentPart

  defstruct [
    :model,
    :temperature,
    :endpoint,
    :api_key
  ]

  @type t :: %__MODULE__{
    model: String.t(),
    temperature: float(),
    endpoint: String.t(),
    api_key: String.t()
  }

  @doc """
  Creates a new instance of the custom LLM adapter.

  ## Examples

      iex> MyApp.CustomLLMAdapter.new!(%{
      ...>   model: "custom-model-v1",
      ...>   temperature: 0.0,
      ...>   endpoint: "https://api.example.com/v1/chat",
      ...>   api_key: "sk-..."
      ...> })
  """
  @impl true
  def new(attrs \\ %{}) do
    %__MODULE__{
      model: attrs[:model] || "default-model",
      temperature: attrs[:temperature] || 0.7,
      endpoint: attrs[:endpoint] || "https://api.example.com/v1/chat",
      api_key: attrs[:api_key]
    }
    |> validate()
  end

  @impl true
  def new!(attrs \\ %{}) do
    case new(attrs) do
      {:ok, adapter} -> adapter
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  defp validate(adapter) do
    cond do
      is_nil(adapter.api_key) ->
        {:error, "API key is required"}

      is_nil(adapter.endpoint) ->
        {:error, "Endpoint URL is required"}

      true ->
        {:ok, adapter}
    end
  end

  @doc """
  Sends messages to the LLM and returns the response.

  This is the main function called by LangChain to get completions.
  """
  @impl true
  def call(adapter, messages, _functions \\ []) do
    # Build the request payload
    payload = build_payload(adapter, messages)

    # Make the API request
    case make_api_request(adapter, payload) do
      {:ok, response_text} ->
        # Convert to LangChain 0.4.0 format
        message = %Message{
          role: :assistant,
          content: [
            %ContentPart{
              type: :text,
              content: response_text
            }
          ],
          status: :complete
        }

        {:ok, message}

      {:error, reason} ->
        {:error, nil, reason}
    end
  end

  defp build_payload(adapter, messages) do
    %{
      model: adapter.model,
      temperature: adapter.temperature,
      messages: Enum.map(messages, &message_to_api_format/1)
    }
  end

  defp message_to_api_format(%Message{role: role, content: content}) do
    %{
      role: to_string(role),
      content: ContentPart.parts_to_string(content)
    }
  end

  defp make_api_request(adapter, payload) do
    headers = [
      {"Authorization", "Bearer #{adapter.api_key}"},
      {"Content-Type", "application/json"}
    ]

    body = Jason.encode!(payload)

    case HTTPoison.post(adapter.endpoint, body, headers) do
      {:ok, %{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
            {:ok, content}

          {:error, _} = error ->
            error
        end

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "API returned status #{status_code}: #{body}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end
end
```

### Streaming Adapter Example

```elixir
defmodule MyApp.StreamingLLMAdapter do
  use LangChain.ChatModels.ChatModel

  alias LangChain.Message
  alias LangChain.Message.ContentPart
  alias LangChain.MessageDelta
  alias LangChain.Chains.LLMChain

  # ... struct and new/new! implementations ...

  @impl true
  def call(adapter, messages, _functions \\ []) do
    # For streaming, we need to handle Server-Sent Events (SSE)
    payload = build_payload(adapter, messages, stream: true)

    # Initialize the delta accumulator
    delta_acc = %MessageDelta{
      role: :assistant,
      content: [],
      status: :incomplete
    }

    case stream_api_request(adapter, payload, delta_acc) do
      {:ok, final_delta} ->
        # Convert final delta to message
        message = MessageDelta.to_message(final_delta)
        {:ok, message}

      {:error, reason} ->
        {:error, nil, reason}
    end
  end

  defp stream_api_request(adapter, payload, delta_acc) do
    headers = [
      {"Authorization", "Bearer #{adapter.api_key}"},
      {"Content-Type", "application/json"},
      {"Accept", "text/event-stream"}
    ]

    body = Jason.encode!(payload)

    # Use streaming HTTP client
    case HTTPoison.post(adapter.endpoint, body, headers, stream_to: self(), async: :once) do
      {:ok, %HTTPoison.AsyncResponse{id: ref}} ->
        receive_stream(ref, delta_acc)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp receive_stream(ref, delta_acc) do
    receive do
      %HTTPoison.AsyncChunk{id: ^ref, chunk: chunk} ->
        # Parse SSE chunk
        case parse_sse_chunk(chunk) do
          {:ok, content_chunk} ->
            # Create a delta for this chunk
            new_delta = %MessageDelta{
              role: :assistant,
              content: [%ContentPart{type: :text, content: content_chunk}],
              status: :incomplete
            }

            # Merge with accumulator
            updated_acc = merge_message_deltas(delta_acc, new_delta)

            # Request next chunk
            HTTPoison.stream_next(%HTTPoison.AsyncResponse{id: ref})
            receive_stream(ref, updated_acc)

          {:done} ->
            # Stream complete
            {:ok, %{delta_acc | status: :complete}}

          {:error, reason} ->
            {:error, reason}
        end

      %HTTPoison.AsyncEnd{id: ^ref} ->
        {:ok, %{delta_acc | status: :complete}}

      %HTTPoison.Error{id: ^ref, reason: reason} ->
        {:error, reason}
    after
      30_000 ->
        {:error, "Stream timeout"}
    end
  end

  defp parse_sse_chunk(chunk) do
    # Parse Server-Sent Events format
    # Example: "data: {\"choices\":[{\"delta\":{\"content\":\"text\"}}]}\n\n"
    case String.trim(chunk) do
      "data: [DONE]" ->
        {:done}

      "data: " <> json_data ->
        case Jason.decode(json_data) do
          {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}} ->
            {:ok, content}

          _ ->
            {:ok, ""}
        end

      _ ->
        {:ok, ""}
    end
  end

  defp merge_message_deltas(acc, new_delta) do
    # Merge content lists
    merged_content = acc.content ++ new_delta.content
    %{acc | content: merged_content}
  end
end
```

## Configuration

### Basic Configuration

```elixir
# config/config.exs
config :gettext_translator, GettextTranslator,
  endpoint: MyApp.CustomLLMAdapter,
  endpoint_model: "custom-model-v1",
  endpoint_temperature: 0,
  endpoint_config: %{
    "api_key" => System.get_env("CUSTOM_LLM_API_KEY"),
    "endpoint" => "https://api.example.com/v1/chat"
  },
  persona: "You are a professional translator. Translate accurately while preserving meaning and length.",
  style: "Casual, using simple language",
  ignored_languages: ["en"]
```

### Runtime Configuration

The `endpoint_config` map is dynamically applied at runtime. GettextTranslator converts config keys to LangChain application environment variables:

```elixir
# This config map:
endpoint_config: %{
  "api_key" => "sk-...",
  "custom_setting" => "value"
}

# Becomes:
Application.put_env(:langchain, :api_key, "sk-...")
Application.put_env(:langchain, :custom_setting, "value")
```

This allows you to configure any LangChain-compatible adapter without code changes.

### Environment-Specific Configuration

```elixir
# config/dev.exs
config :gettext_translator, GettextTranslator,
  endpoint: LangChain.ChatModels.ChatOllamaAI,
  endpoint_model: "llama3.2:latest",
  endpoint_temperature: 0,
  endpoint_config: %{},  # Local Ollama, no config needed
  persona: "You are a professional translator.",
  style: "Casual",
  ignored_languages: ["en"]

# config/prod.exs
config :gettext_translator, GettextTranslator,
  endpoint: LangChain.ChatModels.ChatOpenAI,
  endpoint_model: "gpt-4",
  endpoint_temperature: 0,
  endpoint_config: %{
    "openai_key" => System.get_env("OPENAI_API_KEY")
  },
  persona: "You are a professional translator.",
  style: "Casual",
  ignored_languages: ["en"]
```

## Testing Your Custom Endpoint

### 1. Unit Test Your Adapter

```elixir
# test/my_app/custom_llm_adapter_test.exs
defmodule MyApp.CustomLLMAdapterTest do
  use ExUnit.Case

  alias MyApp.CustomLLMAdapter
  alias LangChain.Message
  alias LangChain.Message.ContentPart

  test "new/1 creates adapter with valid config" do
    {:ok, adapter} = CustomLLMAdapter.new(%{
      model: "test-model",
      api_key: "test-key",
      endpoint: "https://test.com"
    })

    assert adapter.model == "test-model"
    assert adapter.api_key == "test-key"
  end

  test "new/1 validates required fields" do
    assert {:error, _} = CustomLLMAdapter.new(%{model: "test"})
  end

  test "call/2 returns properly formatted message" do
    adapter = CustomLLMAdapter.new!(%{
      model: "test-model",
      api_key: "test-key",
      endpoint: "https://test.com"
    })

    messages = [
      Message.new_user!("Translate 'hello' to Spanish")
    ]

    # Mock the API response
    # ... your mocking logic ...

    assert {:ok, response} = CustomLLMAdapter.call(adapter, messages)
    assert %Message{} = response
    assert response.role == :assistant
    assert is_list(response.content)
    assert [%ContentPart{type: :text, content: text}] = response.content
    assert is_binary(text)
  end
end
```

### 2. Integration Test with GettextTranslator

```elixir
# test/integration/translation_test.exs
defmodule GettextTranslatorIntegrationTest do
  use ExUnit.Case

  test "translates with custom adapter" do
    provider = %{
      ignored_languages: ["en"],
      persona: "Professional translator",
      style: "Casual",
      endpoint: %{
        config: %{
          "api_key" => "test-key"
        },
        adapter: MyApp.CustomLLMAdapter,
        model: "test-model",
        temperature: 0
      }
    }

    opts = %{
      language_code: "es",
      message: "Hello, world!"
    }

    assert {:ok, translation} = GettextTranslator.Processor.LLM.translate(provider, opts)
    assert is_binary(translation)
    assert translation != ""
  end
end
```

### 3. Manual Testing

```bash
# Run translation with your custom adapter
mix gettext_translator.run

# Check logs for errors
tail -f log/dev.log | grep -i "error\|translat"
```

### 4. Verify Response Format

Add logging to verify your adapter returns the correct format:

```elixir
def call(adapter, messages, _functions) do
  case make_api_request(adapter, messages) do
    {:ok, response_text} ->
      message = %Message{
        role: :assistant,
        content: [%ContentPart{type: :text, content: response_text}],
        status: :complete
      }

      # Debug logging
      require Logger
      Logger.debug("Adapter response: #{inspect(message)}")

      {:ok, message}

    {:error, reason} ->
      Logger.error("Adapter error: #{inspect(reason)}")
      {:error, nil, reason}
  end
end
```

## Common Issues

### Issue 1: "content is not a list"

**Error:**
```
** (FunctionClauseError) no function clause matching in ContentPart.parts_to_string/1
```

**Cause:** Your adapter is returning `content` as a string instead of a list of ContentPart structs.

**Solution:**
```elixir
# ❌ WRONG
content: "translated text"

# ✅ CORRECT
content: [%ContentPart{type: :text, content: "translated text"}]
```

### Issue 2: "undefined function ContentPart.new/1"

**Error:**
```
** (UndefinedFunctionError) function LangChain.Message.ContentPart.new/1 is undefined
```

**Cause:** Trying to use `ContentPart.new/1` which doesn't exist.

**Solution:** Use struct syntax instead:
```elixir
# ❌ WRONG
ContentPart.new(%{type: :text, content: "text"})

# ✅ CORRECT
%ContentPart{type: :text, content: "text"}
```

### Issue 3: "pattern match failed on {:ok, result}"

**Error:**
```
** (MatchError) no match of right hand side value: {:ok, %Message{...}}
```

**Cause:** GettextTranslator expects `{:ok, %{last_message: %Message{}}}` but your adapter returns `{:ok, %Message{}}`.

**Solution:** Make sure your LLMChain implementation wraps the message properly:
```elixir
# Your adapter's call/2 should return:
{:ok, %Message{...}}

# LLMChain will wrap it as:
{:ok, %LLMChain{last_message: %Message{...}}}
```

### Issue 4: Empty translations returned

**Symptoms:** Translations complete but return empty strings.

**Possible Causes:**
1. API errors being silently caught
2. Response parsing errors
3. Content extraction failing

**Debug Steps:**
```elixir
# Add detailed logging in your adapter
def call(adapter, messages, _functions) do
  Logger.debug("Sending messages: #{inspect(messages)}")

  case make_api_request(adapter, payload) do
    {:ok, response_text} ->
      Logger.debug("Received response: #{inspect(response_text)}")
      # ... rest of code

    {:error, reason} ->
      Logger.error("API error: #{inspect(reason)}")
      {:error, nil, reason}
  end
end
```

### Issue 5: Streaming not working

**Symptoms:** Streaming responses timeout or fail.

**Checklist:**
- [ ] Endpoint supports Server-Sent Events (SSE)
- [ ] `Accept: text/event-stream` header is set
- [ ] SSE parsing handles `data:` prefix correctly
- [ ] Stream timeout is sufficient (30+ seconds)
- [ ] Deltas are properly merged
- [ ] Final delta has `status: :complete`

## Examples

### Example 1: OpenAI-Compatible Endpoint

Many providers offer OpenAI-compatible APIs. You can use them with the built-in adapter:

```elixir
config :gettext_translator, GettextTranslator,
  endpoint: LangChain.ChatModels.ChatOpenAI,
  endpoint_model: "your-model-name",
  endpoint_temperature: 0,
  endpoint_config: %{
    "openai_key" => System.get_env("API_KEY"),
    "openai_endpoint" => "https://your-provider.com/v1/chat/completions"
  },
  persona: "Professional translator",
  style: "Casual",
  ignored_languages: ["en"]
```

### Example 2: Azure OpenAI

```elixir
config :gettext_translator, GettextTranslator,
  endpoint: LangChain.ChatModels.ChatOpenAI,
  endpoint_model: "gpt-4",
  endpoint_temperature: 0,
  endpoint_config: %{
    "openai_key" => System.get_env("AZURE_OPENAI_KEY"),
    "openai_endpoint" => "https://your-resource.openai.azure.com/openai/deployments/your-deployment/chat/completions?api-version=2023-05-15"
  },
  persona: "Professional translator",
  style: "Casual",
  ignored_languages: ["en"]
```

### Example 3: Local LLM with Ollama

```elixir
# Note: Ollama support may be limited in LangChain 0.4.0
config :gettext_translator, GettextTranslator,
  endpoint: LangChain.ChatModels.ChatOllamaAI,
  endpoint_model: "llama3.2:latest",
  endpoint_temperature: 0,
  endpoint_config: %{
    # Empty if using default local endpoint
  },
  persona: "Professional translator",
  style: "Casual",
  ignored_languages: ["en"]
```

### Example 4: Multiple Providers (Environment-Based)

```elixir
# config/config.exs
config :gettext_translator, GettextTranslator,
  endpoint: System.get_env("LLM_PROVIDER", "ollama") |> provider_module(),
  endpoint_model: System.get_env("LLM_MODEL", "llama3.2:latest"),
  endpoint_temperature: 0,
  endpoint_config: provider_config(),
  persona: "Professional translator",
  style: "Casual",
  ignored_languages: ["en"]

defp provider_module("openai"), do: LangChain.ChatModels.ChatOpenAI
defp provider_module("anthropic"), do: LangChain.ChatModels.ChatAnthropic
defp provider_module("gemini"), do: LangChain.ChatModels.ChatGoogleAI
defp provider_module("ollama"), do: LangChain.ChatModels.ChatOllamaAI
defp provider_module(_), do: LangChain.ChatModels.ChatOpenAI

defp provider_config do
  case System.get_env("LLM_PROVIDER", "ollama") do
    "openai" ->
      %{"openai_key" => System.get_env("OPENAI_API_KEY")}

    "anthropic" ->
      %{"anthropic_key" => System.get_env("ANTHROPIC_API_KEY")}

    "gemini" ->
      %{"google_ai_key" => System.get_env("GOOGLE_AI_KEY")}

    _ ->
      %{}
  end
end
```

## Building Your Own LLM Gateway

If you're running LLMs locally (e.g., in Docker) and want to provide an HTTP API that works with LangChain:

**📘 See [LLM_GATEWAY_EXAMPLE.md](LLM_GATEWAY_EXAMPLE.md)** for a complete, production-ready Elixir implementation that includes:

- OpenAI-compatible HTTP API endpoint
- Queue system with GenStage for backpressure control
- Support for multiple LLM backends (Ollama, vLLM, TGI)
- API key authentication and rate limiting
- Both streaming (SSE) and synchronous responses
- Complete Docker deployment setup

This gateway sits between LangChain clients and your local LLM, handling queuing, authentication, and protocol translation.

## Additional Resources

- [LangChain Elixir Documentation](https://hexdocs.pm/langchain/)
- [LangChain 0.4.0 Changelog](https://hexdocs.pm/langchain/changelog.html)
- [GettextTranslator Repository](https://github.com/marmend-company/gettext_translator)
- [OpenAI API Documentation](https://platform.openai.com/docs/api-reference)
- [Anthropic API Documentation](https://docs.anthropic.com/claude/reference/)
- [Ollama API Documentation](https://github.com/ollama/ollama/blob/main/docs/api.md)
- [vLLM Documentation](https://docs.vllm.ai/)
- [Text Generation Inference](https://github.com/huggingface/text-generation-inference)

## Support

If you encounter issues with custom endpoints:

1. Check this guide for common issues
2. Enable debug logging in your adapter
3. Verify response format matches LangChain 0.4.0 requirements
4. Open an issue on [GitHub](https://github.com/marmend-company/gettext_translator/issues) with:
   - Your adapter code (sanitized)
   - Error messages and stack traces
   - LangChain version
   - Example request/response payloads
