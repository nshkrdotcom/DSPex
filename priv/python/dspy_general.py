#!/usr/bin/env python3
"""
DSPy general purpose bridge for Snakepit.

Handles basic DSPy operations like Predict, ChainOfThought, etc.
"""

import json
import sys
import traceback
import logging
from datetime import datetime

try:
    import dspy
except ImportError:
    print("Error: dspy-ai package not installed. Run: pip install dspy-ai", file=sys.stderr)
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class DSPyBridge:
    """Bridge between Elixir and DSPy for general operations."""
    
    def __init__(self):
        self.modules = {}
        self.signatures = {}
        self.lm = None
        
    def initialize_lm(self, provider="openai", **kwargs):
        """Initialize the language model."""
        if provider == "openai":
            self.lm = dspy.OpenAI(**kwargs)
        elif provider == "anthropic":
            self.lm = dspy.Claude(**kwargs)
        else:
            raise ValueError(f"Unknown provider: {provider}")
            
        dspy.settings.configure(lm=self.lm)
        logger.info(f"Initialized LM provider: {provider}")
        
    def handle_request(self, request):
        """Handle incoming request from Elixir."""
        try:
            operation = request.get("operation")
            args = request.get("args", {})
            opts = request.get("opts", {})
            
            logger.debug(f"Handling operation: {operation}")
            
            # Route to appropriate handler
            if operation == "dspy.Predict":
                return self.handle_predict(args, opts)
            elif operation == "dspy.ChainOfThought":
                return self.handle_chain_of_thought(args, opts)
            elif operation == "dspy.ReAct":
                return self.handle_react(args, opts)
            elif operation == "dspy.ProgramOfThought":
                return self.handle_program_of_thought(args, opts)
            elif operation == "initialize_lm":
                return self.handle_initialize_lm(args)
            else:
                return self.error_response(f"Unknown operation: {operation}")
                
        except Exception as e:
            logger.error(f"Error handling request: {str(e)}", exc_info=True)
            return self.error_response(str(e), traceback.format_exc())
            
    def handle_predict(self, args, opts):
        """Handle basic prediction."""
        signature = self.get_or_create_signature(args["signature"])
        inputs = args["inputs"]
        
        # Create predictor
        predictor = dspy.Predict(signature)
        
        # Execute prediction
        result = predictor(**inputs)
        
        # Extract outputs
        output = {}
        for field in signature.output_fields:
            if hasattr(result, field):
                output[field] = getattr(result, field)
                
        return self.success_response(output)
        
    def handle_chain_of_thought(self, args, opts):
        """Handle chain of thought reasoning."""
        signature = self.get_or_create_signature(args["signature"])
        inputs = args["inputs"]
        
        # Create CoT module
        cot = dspy.ChainOfThought(signature)
        
        # Execute
        result = cot(**inputs)
        
        # Extract outputs including reasoning
        output = {}
        for field in signature.output_fields:
            if hasattr(result, field):
                output[field] = getattr(result, field)
                
        # Include reasoning if available
        if hasattr(result, "rationale"):
            output["reasoning"] = result.rationale
            
        return self.success_response(output)
        
    def handle_react(self, args, opts):
        """Handle ReAct pattern."""
        # This is a placeholder - full ReAct implementation needs tool integration
        return self.error_response("ReAct not yet implemented")
        
    def handle_program_of_thought(self, args, opts):
        """Handle program of thought."""
        # This is a placeholder
        return self.error_response("ProgramOfThought not yet implemented")
        
    def handle_initialize_lm(self, args):
        """Initialize language model configuration."""
        provider = args.get("provider", "openai")
        config = args.get("config", {})
        
        self.initialize_lm(provider, **config)
        
        return self.success_response({"status": "initialized", "provider": provider})
        
    def get_or_create_signature(self, sig_spec):
        """Get or create a DSPy signature."""
        if isinstance(sig_spec, str):
            # Simple string signature
            if sig_spec not in self.signatures:
                self.signatures[sig_spec] = dspy.Signature(sig_spec)
            return self.signatures[sig_spec]
        else:
            # Complex signature with fields
            sig_key = self._signature_key(sig_spec)
            if sig_key not in self.signatures:
                # Create signature from specification
                fields = []
                
                # Add input fields
                for field in sig_spec.get("inputs", []):
                    fields.append(dspy.InputField(
                        prefix=field["name"],
                        desc=field.get("description", "")
                    ))
                    
                # Add output fields
                for field in sig_spec.get("outputs", []):
                    fields.append(dspy.OutputField(
                        prefix=field["name"],
                        desc=field.get("description", "")
                    ))
                    
                self.signatures[sig_key] = dspy.Signature(*fields)
                
            return self.signatures[sig_key]
            
    def _signature_key(self, sig_spec):
        """Generate a key for signature caching."""
        return json.dumps(sig_spec, sort_keys=True)
        
    def success_response(self, result):
        """Create a success response."""
        return {
            "success": True,
            "result": result,
            "timestamp": datetime.utcnow().isoformat()
        }
        
    def error_response(self, error, traceback=None):
        """Create an error response."""
        response = {
            "success": False,
            "error": error,
            "timestamp": datetime.utcnow().isoformat()
        }
        
        if traceback:
            response["traceback"] = traceback
            
        return response


def main():
    """Main entry point for Snakepit worker."""
    logger.info("DSPy bridge starting...")
    
    bridge = DSPyBridge()
    
    # Initialize default LM if environment variables are set
    if "OPENAI_API_KEY" in os.environ:
        bridge.initialize_lm("openai")
    
    # Main request/response loop
    while True:
        try:
            # Read request from stdin (Snakepit protocol)
            request = read_request()
            
            if request is None:
                break
                
            # Handle request
            response = bridge.handle_request(request)
            
            # Write response
            write_response(response)
            
        except KeyboardInterrupt:
            logger.info("Shutting down...")
            break
        except Exception as e:
            logger.error(f"Fatal error: {str(e)}", exc_info=True)
            write_response({
                "success": False,
                "error": f"Fatal error: {str(e)}"
            })


def read_request():
    """Read a request using Snakepit protocol."""
    try:
        # Snakepit sends JSON lines
        line = sys.stdin.readline()
        if not line:
            return None
            
        return json.loads(line)
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON: {e}")
        return None


def write_response(response):
    """Write a response using Snakepit protocol."""
    # Snakepit expects JSON lines
    json_str = json.dumps(response)
    sys.stdout.write(json_str + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    import os
    main()