import Config

# Configure default LLM adapter
config :dspex, :llm,
  default_adapter: :instructor_lite,
  default_provider: :gemini,
  default_model: "gemini/gemini-2.5-flash-lite",
  adapters: [
    instructor_lite: [
      default_provider: :gemini,
      providers: [
        gemini: [
          api_key: {:system, "GEMINI_API_KEY"},
          model: "gemini/gemini-2.5-flash-lite"
        ],
        openai: [
          api_key: {:system, "OPENAI_API_KEY"}
        ],
        anthropic: [
          api_key: {:system, "ANTHROPIC_API_KEY"}
        ]
      ]
    ],
    gemini: [
      auth_strategy: :gemini,
      api_key: {:system, "GEMINI_API_KEY"},
      model: "gemini/gemini-2.5-flash-lite"
    ],
    http: [
      timeout: 60_000,
      pool_size: 10
    ],
    python: [
      pool: :llm_pool,
      script: "llm_bridge.py"
    ]
  ]

# Configure Snakepit with gRPC adapter
config :snakepit,
  pools: [
    default: [
      size: 1,
      max_overflow: 0,
      adapter: Snakepit.Adapters.GRPCPython,
      adapter_args: ["--adapter", "dspex_adapters.dspy_grpc.DSPyGRPCHandler"]
    ]
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
