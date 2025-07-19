import Config

# Configure default LLM adapter
config :dspex, :llm,
  default_adapter: :instructor_lite,
  default_provider: :gemini,
  default_model: "gemini-2.0-flash-exp",
  adapters: [
    instructor_lite: [
      default_provider: :gemini,
      providers: [
        gemini: [
          api_key: {:system, "GEMINI_API_KEY"},
          model: "gemini-2.0-flash-exp"
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
      model: "gemini-2.0-flash-exp"
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

# Configure Snakepit
config :snakepit,
  pools: [
    default: [
      size: 4,
      max_overflow: 2
    ]
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
