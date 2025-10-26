# PyBridge Configuration for DSPy Integration
# This is the actual configuration that would replace the current manual DSPex implementation

defmodule DSPyConfig do
  @moduledoc """
  Complete PyBridge configuration for DSPy library integration.

  This configuration demonstrates how PyBridge would work in practice,
  replacing ~2000+ lines of manual wrapper code with declarative config.

  ## Usage

  Add to your application:

      # config/config.exs
      config :pybridge, :libraries, [
        {DSPex, DSPyConfig}
      ]

  Then use the auto-generated modules:

      {:ok, pred} = DSPex.Predict.create("question -> answer")
      {:ok, result} = DSPex.Predict.call(pred, %{question: "What is DSPy?"})
  """

  use SnakeBridge.Config

  def config do
    %SnakeBridge.Config{
      # === Core Metadata ===
      python_module: "dspy",
      version: "2.5.0",
      description: """
      DSPy: The framework for programming—not prompting—foundation models.
      Provides composable modules for building and optimizing LM pipelines.
      """,

      # === Introspection Settings ===
      introspection: %{
        enabled: true,
        cache_path: "priv/pybridge/schemas/dspy_v2.5.0.json",
        discovery_depth: 3,
        submodules: [
          # Optimizers
          "dspy.teleprompt",
          # Evaluation utilities
          "dspy.evaluate",
          # Retrieval modules
          "dspy.retrieve",
          # Core primitives
          "dspy.primitives",
          # Dataset loaders
          "dspy.datasets",
          # Utilities
          "dspy.utils"
        ],
        exclude_patterns: [
          "test_*",
          "*_test",
          "internal.*",
          "*.experimental.*"
        ]
      },

      # === Core Predictor Classes ===
      classes: [
        # ─────────────────────────────────────────────────────
        # Basic Predictors
        # ─────────────────────────────────────────────────────

        %{
          python_path: "dspy.Predict",
          elixir_module: DSPex.Predict,
          description: "Basic prediction module without intermediate reasoning.",
          constructor: %{
            args: %{
              signature: {:required, :string},
              max_iters: {:optional, :integer}
            },
            session_aware: true,
            timeout: 30_000
          },
          methods: [
            %{
              name: "__call__",
              elixir_name: :call,
              description: "Execute prediction with the given inputs",
              streaming: false,
              # Dynamic kwargs
              args: %{},
              returns: "dict[str, Any]",
              timeout: 60_000
            },
            %{
              name: "forward",
              elixir_name: :forward,
              description: "Forward pass through the predictor",
              streaming: false,
              args: %{},
              returns: "Prediction"
            }
          ],
          result_transform: &DSPex.Transforms.prediction_result/1
        },
        %{
          python_path: "dspy.ChainOfThought",
          elixir_module: DSPex.ChainOfThought,
          description: "Predictor that generates intermediate reasoning steps.",
          extends: DSPex.Predict,
          constructor: %{
            args: %{
              signature: {:required, :string},
              rationale_type: {:optional, :atom},
              max_iters: {:optional, :integer}
            },
            session_aware: true
          },
          methods: [
            %{
              name: "__call__",
              elixir_name: :think,
              description: "Execute chain of thought reasoning",
              # Enable streaming for long reasoning chains
              streaming: true,
              args: %{},
              returns: "dict[str, Any]"
            }
          ],
          result_transform: &DSPex.Transforms.chain_of_thought_result/1
        },
        %{
          python_path: "dspy.ChainOfThoughtWithHint",
          elixir_module: DSPex.ChainOfThoughtWithHint,
          description: "Chain of thought with external hints/guidance.",
          extends: DSPex.ChainOfThought,
          constructor: %{
            args: %{
              signature: {:required, :string},
              hint: {:optional, :string}
            },
            session_aware: true
          }
        },
        %{
          python_path: "dspy.ProgramOfThought",
          elixir_module: DSPex.ProgramOfThought,
          description: "Generates executable code to solve problems.",
          constructor: %{
            args: %{
              signature: {:required, :string},
              max_iters: {:optional, :integer}
            },
            session_aware: true
          },
          methods: [
            %{
              name: "__call__",
              elixir_name: :reason,
              description: "Generate and execute program of thought",
              streaming: false,
              args: %{}
            },
            %{
              name: "execute_code",
              elixir_name: :execute_code,
              description: "Execute generated Python code",
              streaming: false,
              args: %{
                code: {:required, :string},
                context: {:optional, :map}
              }
            }
          ]
        },
        %{
          python_path: "dspy.ReAct",
          elixir_module: DSPex.ReAct,
          description: "Reasoning and Acting agent with tool use.",
          constructor: %{
            args: %{
              signature: {:required, :string},
              tools: {:optional, :list},
              max_iters: {:optional, :integer}
            },
            session_aware: true
          },
          methods: [
            %{
              name: "__call__",
              elixir_name: :act,
              description: "Execute ReAct loop with reasoning and actions",
              streaming: true,
              args: %{}
            }
          ]
        },
        %{
          python_path: "dspy.MultiChainComparison",
          elixir_module: DSPex.MultiChainComparison,
          description: "Compare multiple reasoning chains and select the best.",
          constructor: %{
            args: %{
              signature: {:required, :string},
              num_chains: {:optional, :integer},
              comparison_metric: {:optional, :function}
            },
            session_aware: true
          },
          methods: [
            %{
              name: "__call__",
              elixir_name: :compare,
              streaming: false,
              args: %{}
            }
          ]
        },

        # ─────────────────────────────────────────────────────
        # Retrieval Modules
        # ─────────────────────────────────────────────────────

        %{
          python_path: "dspy.Retrieve",
          elixir_module: DSPex.Retrieve,
          description: "Basic retrieval module for document search.",
          constructor: %{
            args: %{
              k: {:optional, :integer}
            },
            session_aware: true
          },
          methods: [
            %{
              name: "__call__",
              elixir_name: :retrieve,
              description: "Retrieve top-k documents for a query",
              streaming: false,
              args: %{
                query: {:required, :string},
                k: {:optional, :integer}
              },
              returns: "list[str]"
            },
            %{
              name: "forward",
              elixir_name: :forward,
              streaming: false,
              args: %{}
            }
          ]
        },

        # ─────────────────────────────────────────────────────
        # Language Model Clients
        # ─────────────────────────────────────────────────────

        %{
          python_path: "dspy.OpenAI",
          elixir_module: DSPex.LM.OpenAI,
          description: "OpenAI language model client.",
          constructor: %{
            args: %{
              model: {:optional, :string},
              api_key: {:optional, :string},
              api_base: {:optional, :string},
              model_type: {:optional, :string},
              max_tokens: {:optional, :integer},
              temperature: {:optional, :float},
              cache_seed: {:optional, :integer}
            },
            # LM clients can be stateless
            session_aware: false
          },
          methods: [
            %{
              name: "__call__",
              elixir_name: :generate,
              description: "Generate completion",
              streaming: true,
              args: %{
                prompt: {:required, :string_or_list},
                max_tokens: {:optional, :integer}
              }
            },
            %{
              name: "request",
              elixir_name: :request,
              description: "Low-level API request",
              streaming: false,
              args: %{}
            }
          ]
        },
        %{
          python_path: "dspy.Anthropic",
          elixir_module: DSPex.LM.Anthropic,
          description: "Anthropic (Claude) language model client.",
          constructor: %{
            args: %{
              model: {:optional, :string},
              api_key: {:optional, :string},
              max_tokens: {:optional, :integer}
            },
            session_aware: false
          },
          methods: [
            %{
              name: "__call__",
              elixir_name: :generate,
              streaming: true,
              args: %{}
            }
          ]
        },
        %{
          python_path: "dspy.Cohere",
          elixir_module: DSPex.LM.Cohere,
          description: "Cohere language model client.",
          constructor: %{
            args: %{
              model: {:optional, :string},
              api_key: {:optional, :string}
            },
            session_aware: false
          }
        },
        %{
          python_path: "dspy.Together",
          elixir_module: DSPex.LM.Together,
          description: "Together AI language model client.",
          constructor: %{
            args: %{
              model: {:optional, :string},
              api_key: {:optional, :string}
            },
            session_aware: false
          }
        },

        # ─────────────────────────────────────────────────────
        # Optimizers (Teleprompt)
        # ─────────────────────────────────────────────────────

        %{
          python_path: "dspy.teleprompt.BootstrapFewShot",
          elixir_module: DSPex.Optimizers.BootstrapFewShot,
          description: "Bootstrap few-shot examples for optimization.",
          constructor: %{
            args: %{
              metric: {:optional, :function},
              max_bootstrapped_demos: {:optional, :integer},
              max_labeled_demos: {:optional, :integer},
              max_rounds: {:optional, :integer},
              max_errors: {:optional, :integer}
            },
            session_aware: true
          },
          methods: [
            %{
              name: "compile",
              elixir_name: :compile,
              description: "Compile/optimize a DSPy program",
              streaming: false,
              args: %{
                student: {:required, :any},
                trainset: {:required, :list},
                teacher: {:optional, :any},
                valset: {:optional, :list}
              },
              # 5 minutes for optimization
              timeout: 300_000
            }
          ]
        },
        %{
          python_path: "dspy.teleprompt.MIPRO",
          elixir_module: DSPex.Optimizers.MIPRO,
          description: "Multi-prompt optimization with instructions.",
          constructor: %{
            args: %{
              metric: {:required, :function},
              num_candidates: {:optional, :integer},
              init_temperature: {:optional, :float},
              verbose: {:optional, :boolean}
            },
            session_aware: true
          },
          methods: [
            %{
              name: "compile",
              elixir_name: :compile,
              streaming: false,
              args: %{
                student: {:required, :any},
                trainset: {:required, :list},
                num_trials: {:optional, :integer},
                max_bootstrapped_demos: {:optional, :integer}
              },
              # 10 minutes
              timeout: 600_000
            }
          ]
        },
        %{
          python_path: "dspy.teleprompt.BootstrapFewShotWithRandomSearch",
          elixir_module: DSPex.Optimizers.BootstrapWithRandomSearch,
          description: "Bootstrap with random search over hyperparameters.",
          constructor: %{
            args: %{
              metric: {:required, :function},
              num_candidate_programs: {:optional, :integer},
              num_threads: {:optional, :integer}
            },
            session_aware: true
          }
        },
        %{
          python_path: "dspy.teleprompt.KNNFewShot",
          elixir_module: DSPex.Optimizers.KNNFewShot,
          description: "K-nearest neighbors few-shot selection.",
          constructor: %{
            args: %{
              k: {:optional, :integer},
              trainset: {:required, :list}
            },
            session_aware: true
          }
        },

        # ─────────────────────────────────────────────────────
        # Primitives & Core Types
        # ─────────────────────────────────────────────────────

        %{
          python_path: "dspy.Signature",
          elixir_module: DSPex.Signature,
          description: "DSPy signature definition.",
          singleton: true,
          constructor: %{
            args: %{
              spec: {:required, :string},
              instructions: {:optional, :string}
            },
            session_aware: false
          },
          methods: [
            %{
              name: "fields",
              elixir_name: :fields,
              description: "Get signature fields",
              streaming: false,
              args: %{}
            },
            %{
              name: "with_instructions",
              elixir_name: :with_instructions,
              description: "Add instructions to signature",
              streaming: false,
              args: %{
                instructions: {:required, :string}
              }
            }
          ]
        },
        %{
          python_path: "dspy.Example",
          elixir_module: DSPex.Example,
          description: "Training/validation example container.",
          constructor: %{
            args: %{
              data: {:required, :map}
            },
            session_aware: false
          },
          methods: [
            %{
              name: "with_inputs",
              elixir_name: :with_inputs,
              description: "Mark certain fields as inputs",
              streaming: false,
              args: %{
                fields: {:required, :list}
              }
            }
          ]
        },
        %{
          python_path: "dspy.Prediction",
          elixir_module: DSPex.Prediction,
          description: "Prediction result container.",
          constructor: %{
            args: %{
              data: {:optional, :map}
            },
            session_aware: false
          },
          properties: [
            %{
              name: "completions",
              elixir_name: :completions,
              type: "list",
              readonly: true
            }
          ]
        }
      ],

      # === Standalone Functions ===
      functions: [
        %{
          python_path: "dspy.settings.configure",
          elixir_name: :configure,
          description: "Configure global DSPy settings (LM, RM, etc.)",
          args: %{
            lm: {:optional, :any},
            rm: {:optional, :any},
            adapter: {:optional, :string},
            experimental: {:optional, :boolean}
          },
          # Side effects
          pure: false,
          cacheable: false
        },
        %{
          python_path: "dspy.assert_transform_module",
          elixir_name: :assert_transform_module,
          description: "Transform assertions in a module",
          args: %{
            module: {:required, :any},
            backtrack_handler: {:optional, :function}
          },
          pure: true
        },
        %{
          python_path: "dspy.Suggest",
          elixir_name: :suggest,
          description: "Create a suggestion assertion",
          args: %{
            condition: {:required, :boolean},
            message: {:optional, :string}
          },
          pure: true
        },
        %{
          python_path: "dspy.Assert",
          elixir_name: :assert,
          description: "Create a hard assertion",
          args: %{
            condition: {:required, :boolean},
            message: {:optional, :string}
          },
          pure: true
        }
      ],

      # === Bidirectional Tools ===
      bidirectional_tools: %{
        enabled: true,
        export_to_python: [
          # Validators
          %{
            module: DSPex.Validators,
            function: :validate_reasoning,
            arity: 1,
            python_name: "elixir_validate_reasoning",
            description: "Validate reasoning chain structure and quality",
            async: false
          },
          %{
            module: DSPex.Validators,
            function: :validate_output,
            arity: 2,
            python_name: "elixir_validate_output",
            description: "Validate output against signature constraints",
            async: false
          },
          %{
            module: DSPex.Validators,
            function: :check_hallucination,
            arity: 2,
            python_name: "elixir_check_hallucination",
            description: "Check for hallucinations in output",
            async: false
          },

          # Metrics
          %{
            module: DSPex.Metrics,
            function: :track_prediction,
            arity: 2,
            python_name: "elixir_track_prediction",
            description: "Track prediction metrics in Elixir telemetry",
            async: true
          },
          %{
            module: DSPex.Metrics,
            function: :accuracy,
            arity: 2,
            python_name: "elixir_accuracy",
            description: "Calculate accuracy metric",
            async: false
          },

          # Transforms
          %{
            module: DSPex.Transforms,
            function: :post_process,
            arity: 1,
            python_name: "elixir_post_process",
            description: "Post-process prediction results",
            async: false
          },
          %{
            module: DSPex.Transforms,
            function: :format_for_domain,
            arity: 2,
            python_name: "elixir_format_domain",
            description: "Format output for specific domain",
            async: false
          },

          # Custom Tools
          %{
            module: DSPex.Tools,
            function: :semantic_cache_lookup,
            arity: 2,
            python_name: "elixir_cache_lookup",
            description: "Check semantic cache for similar queries",
            async: true
          },
          %{
            module: DSPex.Tools,
            function: :retrieve_from_elixir_db,
            arity: 1,
            python_name: "elixir_db_retrieve",
            description: "Retrieve data from Elixir-side database",
            async: true
          }
        ]
      },

      # === gRPC Configuration ===
      grpc: %{
        enabled: true,
        service_name: "dspy",
        streaming_methods: [
          "stream_completion",
          "generate_stream",
          "ChainOfThought.__call__",
          "ReAct.__call__",
          "OpenAI.generate",
          "Anthropic.generate"
        ],
        # 16MB for large prompts
        max_message_size: 16_777_216
      },

      # === Caching Configuration ===
      caching: %{
        enabled: true,
        # 1 hour
        ttl: 3600,
        cache_pure_functions: true,
        cache_keys: [
          # Cache signature parsing
          {DSPex.Signature, :parse, [:spec]},
          # Cache introspection results
          {DSPex.Bridge, :discover_schema, [:module_path]}
        ]
      },

      # === Telemetry Configuration ===
      telemetry: %{
        enabled: true,
        prefix: [:dspex],
        metrics: [
          "duration",
          "count",
          "errors",
          "cache_hits",
          "cache_misses",
          "token_usage",
          "cost"
        ],
        custom_metadata: [
          :signature,
          :model,
          :temperature,
          :session_id
        ]
      }
    }
  end

  # ═══════════════════════════════════════════════════════════
  # Custom Transform Functions
  # ═══════════════════════════════════════════════════════════

  @doc """
  Placeholder transform modules that would be implemented in DSPex.

  These handle the conversion between Python DSPy results and
  idiomatic Elixir data structures.
  """

  defmodule DSPex.Transforms do
    def prediction_result(%{"completions" => completions}) when is_list(completions) do
      %{
        success: true,
        prediction: List.first(completions),
        all_completions: completions
      }
    end

    def prediction_result(result) when is_map(result) do
      %{success: true, prediction: result}
    end

    def chain_of_thought_result(%{"reasoning" => reasoning, "answer" => answer}) do
      %{
        success: true,
        reasoning: reasoning,
        answer: answer
      }
    end

    def chain_of_thought_result(result), do: prediction_result(result)

    def post_process(result), do: result
    def format_for_domain(result, _domain), do: result
  end

  defmodule DSPex.Validators do
    def validate_reasoning(_reasoning), do: %{valid: true}
    def validate_output(_output, _signature), do: %{valid: true}
    def check_hallucination(_output, _context), do: %{hallucinated: false}
  end

  defmodule DSPex.Metrics do
    def track_prediction(_prediction, _metadata), do: :ok
    def accuracy(_prediction, _example), do: 1.0
  end

  defmodule DSPex.Tools do
    def semantic_cache_lookup(_query, _opts), do: {:miss, nil}
    def retrieve_from_elixir_db(_query), do: {:ok, []}
  end
end
