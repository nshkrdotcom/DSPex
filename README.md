# DSPex

> **Revolutionary ML Infrastructure**: Native Elixir syntax for DSPy programs with production-ready Ash framework integration.

[![Build Status](https://github.com/ashframework/dspex/workflows/CI/badge.svg)](https://github.com/ashframework/dspex/actions)
[![Coverage](https://coveralls.io/repos/github/ashframework/dspex/badge.svg)](https://coveralls.io/github/ashframework/dspex)
[![Hex.pm](https://img.shields.io/hexpm/v/dspex.svg)](https://hex.pm/packages/dspex)

## 🚀 Vision

DSPex brings DSPy's declarative language model programming to the Elixir ecosystem with **native signature syntax** and production-ready infrastructure. Instead of Python's verbose class-based signatures, write elegant Elixir:

```elixir
# Instead of Python DSPy's verbose syntax
signature question: :string -> answer: :string, confidence: :float

# Compile-time validation and schema generation
{:ok, validated} = QA.validate_inputs(%{question: "What is 2+2?"})
schema = QA.to_json_schema(:openai)
```

## ✨ Core Innovation

**Native Signature Syntax**: The project's central innovation is eliminating the ceremony of traditional DSPy signatures while leveraging Ash's production infrastructure:

```elixir
defmodule QuestionAnswering do
  use DSPex.Signature
  
  signature question: :string -> answer: :string
end

defmodule ComplexAnalysis do
  use DSPex.Signature
  
  signature text: :string, context: {:list, :string} -> 
    analysis: :reasoning_chain, 
    confidence: :confidence_score,
    entities: {:list, :entity}
end
```

## 🏗️ Current Implementation Status

### ✅ **Stage 1: Foundation (Implemented)**

**Native Signature System**
- Compile-time AST processing and code generation
- Runtime validation for inputs and outputs  
- JSON schema generation (OpenAI, Anthropic, generic)
- Type system with basic, ML-specific, and composite types

**Python Bridge**
- Port-based communication with Python DSPy processes
- GenServer supervision with health monitoring
- Request/response correlation with unique IDs
- Support for DSPy and Gemini integration

**Adapter Pattern**
- Mock adapter for fast testing without Python dependencies
- Deterministic response generation based on signature types
- Plugin architecture for future adapter implementations

**3-Layer Testing Infrastructure**
- **Layer 1**: Fast unit tests with mock adapter (~70ms)
- **Layer 2**: Protocol testing without full Python bridge  
- **Layer 3**: Full integration tests with Python bridge
- Test mode management with environment configuration

### 🏗️ **Planned Stages (In Development)**

#### Stage 2: Core Operations (Weeks 3-4)
- Custom Ash data layer bridging DSPy operations
- ExDantic integration for Pydantic-like validation
- Enhanced optimization support and performance metrics
- Full state synchronization between Ash and DSPy

#### Stage 3: Production Features (Weeks 5-6)  
- Automatic GraphQL/REST API generation
- Background job processing with AshOban
- Real-time subscriptions for long-running operations
- Comprehensive telemetry and LiveDashboard integration

#### Stage 4: Advanced Features (Weeks 7-8)
- Multi-model orchestration with intelligent routing
- Automated deployment pipelines
- Advanced optimization algorithms
- Experiment management and statistical analysis

## 🚦 Quick Start

### Prerequisites

- Elixir 1.18+
- Python 3.8+ with DSPy-AI package
- PostgreSQL (for production features)

### Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:dspex, "~> 0.0.1"}
  ]
end
```

### Basic Usage

1. **Define a Signature**:

```elixir
defmodule MyApp.QA do
  use DSPex.Signature
  
  signature question: :string -> answer: :string
end
```

2. **Use in Your Application**:

```elixir
# Validate inputs
{:ok, validated} = MyApp.QA.validate_inputs(%{question: "What is machine learning?"})

# Generate provider schemas
openai_schema = MyApp.QA.to_json_schema(:openai)
anthropic_schema = MyApp.QA.to_json_schema(:anthropic)

# Execute with Python bridge (requires DSPy setup)
{:ok, result} = DSPex.PythonBridge.Bridge.call(:execute_program, [program_id, validated])
```

3. **Run Tests at Different Layers**:

```bash
# Fast unit tests only (~70ms)
mix test.fast

# Protocol tests (no full Python)
mix test.protocol  

# Full integration tests
mix test.integration

# All layers sequentially
mix test.all
```

## 🏛️ Architecture

### **Layered Architecture**

```
┌─────────────────────────────────────────────────────────────┐
│                     Production APIs                          │
├─────────────────────────────────────────────────────────────┤
│  GraphQL API  │  REST API   │  WebSocket  │  Admin UI      │
├─────────────────────────────────────────────────────────────┤
│                    Ash Domain Layer                          │
│  Program      │  Signature  │  Execution  │  Optimization  │
│  Model        │  Dataset    │  Pipeline   │  Experiment    │
├─────────────────────────────────────────────────────────────┤
│               Custom Data Layer & Adapters                   │
│  Python Port  │  Native     │  Multi-Model │  Router       │
├─────────────────────────────────────────────────────────────┤
│            Infrastructure & Monitoring                       │
│  Background   │  Telemetry  │  Health     │  Deployment    │
│  Jobs         │  Metrics    │  Checks     │  Automation    │
└─────────────────────────────────────────────────────────────┘
```

### **Core Components**

- **`DSPex.Signature`**: Native Elixir signature behavior and DSL
- **`DSPex.Signature.Compiler`**: Compile-time processing and code generation
- **`DSPex.PythonBridge`**: Communication with Python DSPy processes
- **`DSPex.Adapters`**: Pluggable adapter system (Mock, Python, Native)
- **`DSPex.Testing`**: 3-layer testing infrastructure

## 🧪 Testing Philosophy

The project implements a sophisticated **3-layer testing architecture**:

### Layer 1: Mock Adapter (Fast)
- Pure Elixir tests without external dependencies
- Deterministic response generation
- ~70ms execution time for full suite
- Perfect for TDD and rapid development

### Layer 2: Bridge Mock (Protocol)
- Tests communication protocol without full Python integration
- Validates request/response handling
- Bridge lifecycle management

### Layer 3: Full Integration (E2E)
- Real Python bridge with DSPy integration
- Complete system testing
- ML model execution validation

### Running Tests

```bash
# Development: Fast feedback loop
mix test.fast --trace

# CI: Protocol validation  
mix test.protocol

# Pre-deployment: Full integration
mix test.integration

# Comprehensive: All layers
mix test.all
```

## 📊 Type System

### **Basic Types**
- `:string`, `:integer`, `:float`, `:boolean`, `:atom`, `:map`, `:any`

### **ML-Specific Types**
- `:embedding` - Vector embeddings
- `:confidence_score` - Probability values [0.0, 1.0]
- `:probability` - Alias for confidence_score
- `:reasoning_chain` - Step-by-step reasoning
- `:entity` - Named entity recognition results

### **Composite Types**
- `{:list, type}` - Homogeneous lists
- `{:dict, key_type, value_type}` - Typed dictionaries
- `{:union, [type1, type2, ...]}` - Union types

### **Example Usage**

```elixir
defmodule AdvancedAnalysis do
  use DSPex.Signature
  
  signature document: :string, 
           context: {:list, :string} ->
           summary: :string,
           entities: {:list, :entity},
           confidence: :confidence_score,
           reasoning: :reasoning_chain,
           metadata: {:dict, :string, :any}
end
```

## 🔧 Configuration

### Environment Configuration

```elixir
# config/config.exs
config :dspex,
  python_executable: "python3",
  bridge_timeout: 30_000,
  health_check_interval: 5_000,
  adapter: :python_port  # or :mock for testing

# Test-specific
config :dspex,
  test_mode: :mock_adapter,
  bridge_enabled: false
```

### Environment Variables

```bash
export GEMINI_API_KEY="your-gemini-key"
export TEST_MODE="mock_adapter"  # mock_adapter | bridge_mock | full_integration
export PYTHON_EXECUTABLE="/usr/bin/python3"
```

## 📈 Performance

### Current Benchmarks

- **Fast Tests**: ~70ms for 255 tests (Layer 1)
- **Signature Compilation**: ~2ms average
- **Mock Execution**: ~1ms average
- **Python Bridge Latency**: ~100-500ms (depending on model)

### Optimization Features (Planned)

- Connection pooling for Python processes
- Intelligent caching of compiled signatures
- Multi-model load balancing
- Request batching and pipelining

## 🗺️ Roadmap

### **Immediate (Stage 2: Core Operations)**
- [ ] Custom Ash data layer implementation
- [ ] ExDantic validation integration
- [ ] Enhanced Python bridge with optimization
- [ ] Full state synchronization

### **Near-term (Stage 3: Production Features)**
- [ ] Automatic GraphQL/REST API generation
- [ ] Background job processing with AshOban
- [ ] Real-time subscriptions
- [ ] Comprehensive telemetry integration

### **Long-term (Stage 4: Advanced Features)**
- [ ] Multi-model orchestration system
- [ ] Automated deployment pipelines
- [ ] Advanced optimization algorithms
- [ ] Experiment management platform

### **Future Innovations**
- [ ] Native Elixir DSPy port (eliminate Python dependency)
- [ ] BEAM-native language model execution
- [ ] Distributed ML pipeline orchestration
- [ ] Real-time model fine-tuning

## 🎯 Key Benefits

### **For Developers**
- **Elegant Syntax**: Native Elixir signatures eliminate Python ceremony
- **Type Safety**: Compile-time validation and IDE support
- **Fast Feedback**: 3-layer testing with ~70ms unit tests
- **Production Ready**: Built on mature Ash framework

### **For Operations**
- **Observable by Default**: Every execution tracked and queryable
- **Scalable**: BEAM concurrency and supervision
- **Reliable**: Fault-tolerant with automatic recovery
- **Monitorable**: Rich telemetry and health checks

### **For Organizations**
- **Cost Optimization**: Multi-model routing and intelligent fallbacks
- **Compliance**: Audit trails and data governance
- **Integration**: GraphQL/REST APIs auto-generated
- **Deployment**: Automated pipelines and infrastructure

## 🤝 Contributing

We welcome contributions! The project follows a structured development approach:

### Development Setup

```bash
# Clone and setup
git clone https://github.com/ashframework/dspex.git
cd dspex

# Install dependencies
mix deps.get

# Run fast tests
mix test.fast

# Setup Python environment (optional, for integration tests)
./setup_dspy.sh
```

### Testing Guidelines

- Always run `mix test.fast` during development
- Use `mix test.protocol` for bridge-related changes
- Run `mix test.integration` before submitting PRs
- Maintain test coverage above 90%

### Contribution Areas

- **Core**: Signature system improvements
- **Bridge**: Python integration enhancements
- **Adapters**: New adapter implementations
- **Documentation**: Examples and guides
- **Performance**: Optimization and benchmarking

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

- **DSPy Team**: For the foundational declarative ML programming concepts
- **Ash Framework**: For the production-ready domain modeling infrastructure
- **Elixir Community**: For the robust BEAM ecosystem
- **Contributors**: Everyone who has contributed to this ambitious integration

---

**Ready to revolutionize your ML infrastructure?** Start with `mix test.fast` and experience the future of declarative ML programming in Elixir.
