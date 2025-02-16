# GettextTranslator

**TODO: Add description**
**TODO: Add changelog link**
**TODO: Add Github Actions**


## Installation

The package can be installed by adding `gettext_translator` to your list of dependencies in `mix.exs`:

```elixir
def deps do 
  [
    {:gettext_translator, "~> 0.1.0"}
  ]
end
```

## Usage

### Add Provicer Config

Add the following to your `config/config.exs` file:

#### Ollama AI 
```elixir
config :gettext_translator,
  endpoint: LangChain.ChatModels.ChatOllamaAI,
  endpoint_model: "llama3.2:latest",
  endpoint_temperature: 0,
  endpoint_config: %{}, <---Keep Empty, if runned locally ollama with default API endpoint
  persona: "You are a proffesional translator. Your goal is to translate the message to the target language and try to keep the same meaning and length of the output sentence as original one.",
  style: "Casual, use simple language",
  ignored_languages: ["en"]
```
#### OpenAI
```elixir
config :gettext_translator,
  endpoint: LangChain.ChatModels.ChatOpenAI,
  endpoint_model: "gpt-4",
  endpoint_temperature: 0,
  endpoint_config: %{
    "openai_key" =>
      "<YOUR_OPENAI_KEY>",
    "openai_org_id" => "<YOUR_ORG_ID>"
  },
  persona: "You are a proffesional translator. Your goal is to translate the message to the target language and try to keep the same meaning and length of the output sentence as original one.",
  style: "Casual, use simple language",
  ignored_languages: ["en"]
```

### Run Translator with CLI

#### Translate using default gettext folder (priv/gettext)

```elixir
mix gettext_translator.run
```

#### Translate using specific gettext folder

```elixir
mix gettext_translator.run my_path/gettext
```

## Documentation

Documentation can be found on [HexDocs](https://hexdocs.pm/gettext_translator).