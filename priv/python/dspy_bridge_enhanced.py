"""
Enhanced DSPy Bridge with Variable-Aware Module Support

This module extends the existing dspy_bridge.py to support variable-aware
DSPy modules when a session context is available. It can be integrated into
the existing bridge or used as a reference for adding variable support.
"""

import sys
import os

# Import the original bridge
from dspy_bridge import DSPyBridge, DSPY_AVAILABLE

# Add snakepit bridge to path if needed
snakepit_path = os.path.join(os.path.dirname(__file__), '../../snakepit/priv/python')
if snakepit_path not in sys.path:
    sys.path.insert(0, snakepit_path)

# Import variable-aware components
try:
    from snakepit_bridge.dspy_integration import (
        VariableAwarePredict,
        VariableAwareChainOfThought,
        VariableAwareReAct,
        VariableAwareProgramOfThought,
        ModuleVariableResolver,
        create_variable_aware_program
    )
    from snakepit_bridge.session_context import SessionContext, get_or_create_session
    VARIABLE_AWARE_AVAILABLE = True
except ImportError as e:
    print(f"Warning: Variable-aware modules not available: {e}", file=sys.stderr)
    VARIABLE_AWARE_AVAILABLE = False


class EnhancedDSPyBridge(DSPyBridge):
    """
    Enhanced DSPy Bridge that supports variable-aware modules.
    
    This extends the base DSPyBridge to automatically use variable-aware
    modules when a session context is available, enabling automatic
    synchronization of module parameters with DSPex Variables.
    """
    
    def __init__(self, mode="standalone", worker_id=None):
        """Initialize enhanced bridge with variable support."""
        super().__init__(mode, worker_id)
        
        # Track session contexts for variable-aware modules
        self._session_contexts = {}
        
        # Enable variable-aware features
        self.variable_aware_enabled = VARIABLE_AWARE_AVAILABLE
        
        if self.variable_aware_enabled:
            print("Variable-aware DSPy modules enabled", file=sys.stderr)
    
    def _get_or_create_session_context(self, session_id):
        """Get or create a session context for variable management."""
        if not self.variable_aware_enabled:
            return None
        
        if session_id not in self._session_contexts:
            try:
                # Create session context
                # In pool-worker mode, we should have gRPC connection info
                if self.mode == "pool-worker":
                    # TODO: Get actual gRPC connection details from worker context
                    ctx = get_or_create_session(session_id)
                else:
                    # Standalone mode - create local context
                    ctx = SessionContext(session_id=session_id)
                
                self._session_contexts[session_id] = ctx
            except Exception as e:
                print(f"Failed to create session context: {e}", file=sys.stderr)
                return None
        
        return self._session_contexts[session_id]
    
    def create_program(self, args):
        """
        Enhanced program creation with variable-aware support.
        
        If variable_aware is enabled in args and a session_id is provided,
        creates a variable-aware module that automatically syncs with
        DSPex Variables.
        """
        # Check if variable-aware is requested
        use_variable_aware = (
            self.variable_aware_enabled and
            args.get('variable_aware', False) and
            args.get('session_id')
        )
        
        if use_variable_aware:
            return self._create_variable_aware_program(args)
        else:
            # Fall back to standard program creation
            return super().create_program(args)
    
    def _create_variable_aware_program(self, args):
        """Create a variable-aware DSPy program."""
        program_id = args.get('id')
        session_id = args.get('session_id')
        signature_def = args.get('signature', {})
        program_type = args.get('program_type', 'predict')
        variable_bindings = args.get('variable_bindings', {})
        
        if not session_id:
            raise ValueError("Session ID required for variable-aware programs")
        
        # Get session context
        ctx = self._get_or_create_session_context(session_id)
        if not ctx:
            raise RuntimeError("Failed to create session context")
        
        # Map program types to variable-aware versions
        type_mapping = {
            'predict': 'VariableAwarePredict',
            'chain_of_thought': 'VariableAwareChainOfThought',
            'react': 'VariableAwareReAct',
            'program_of_thought': 'VariableAwareProgramOfThought'
        }
        
        module_type = type_mapping.get(program_type, 'VariableAwarePredict')
        
        # Create signature string from definition
        if signature_def.get('inputs') and signature_def.get('outputs'):
            # Build signature string
            inputs = ", ".join(f.get('name', '') for f in signature_def.get('inputs', []))
            outputs = ", ".join(f.get('name', '') for f in signature_def.get('outputs', []))
            signature_str = f"{inputs} -> {outputs}"
        else:
            signature_str = "question -> answer"
        
        try:
            # Create variable-aware module
            module = create_variable_aware_program(
                module_type=module_type.replace('VariableAware', ''),
                signature=signature_str,
                session_context=ctx,
                variable_bindings=variable_bindings,
                auto_bind_common=args.get('auto_bind_common', True)
            )
            
            # Store program info
            program_info = {
                'program': module,
                'signature_def': signature_def,
                'signature_str': signature_str,
                'type': program_type,
                'created_at': time.time(),
                'execution_count': 0,
                'last_executed': None,
                'variable_aware': True,
                'session_id': session_id,
                'variable_bindings': module.get_bindings()
            }
            
            # Store based on mode
            if self.mode == "pool-worker":
                # In pool mode, we might want to register this with SessionStore
                # For now, keep it in memory
                pass
            else:
                self.programs[program_id] = program_info
            
            return {
                "id": program_id,
                "status": "created",
                "type": program_type,
                "variable_aware": True,
                "bindings": module.get_bindings()
            }
            
        except Exception as e:
            return {"error": f"Failed to create variable-aware program: {str(e)}"}
    
    def execute_program(self, args):
        """
        Enhanced program execution with automatic variable sync.
        
        If the program is variable-aware, syncs variables before execution.
        """
        program_id = args.get('id')
        
        # Get program info
        if self.mode == "pool-worker":
            program_info = self._get_program_from_session(args.get('session_id'), program_id)
        else:
            program_info = self.programs.get(program_id)
        
        if not program_info:
            return {"error": f"Program not found: {program_id}"}
        
        # Check if variable-aware
        if program_info.get('variable_aware'):
            return self._execute_variable_aware_program(program_info, args)
        else:
            # Fall back to standard execution
            return super().execute_program(args)
    
    def _execute_variable_aware_program(self, program_info, args):
        """Execute a variable-aware program with automatic sync."""
        program = program_info['program']
        inputs = args.get('inputs', {})
        
        try:
            # Sync variables before execution
            if hasattr(program, 'sync_variables_sync'):
                updates = program.sync_variables_sync()
                if updates:
                    debug_log(f"Synced variables before execution: {updates}")
            
            # Execute program
            result = program(**inputs)
            
            # Update execution stats
            program_info['execution_count'] += 1
            program_info['last_executed'] = time.time()
            
            # Extract outputs
            outputs = {}
            signature_def = program_info.get('signature_def', {})
            
            for field in signature_def.get('outputs', []):
                field_name = field['name']
                if hasattr(result, field_name):
                    outputs[field_name] = getattr(result, field_name)
                else:
                    # Try common fallbacks
                    if hasattr(result, 'answer'):
                        outputs[field_name] = result.answer
                    else:
                        outputs[field_name] = str(result)
            
            return {
                "outputs": outputs,
                "execution_time": time.time() - program_info['last_executed'],
                "variable_aware": True,
                "synced_variables": list(updates.keys()) if 'updates' in locals() else []
            }
            
        except Exception as e:
            self.error_count += 1
            return {"error": str(e)}
    
    def get_program_info(self, args):
        """Enhanced program info including variable bindings."""
        result = super().get_program_info(args)
        
        if 'error' not in result:
            program_id = args.get('id')
            
            if self.mode == "pool-worker":
                program_info = self._get_program_from_session(args.get('session_id'), program_id)
            else:
                program_info = self.programs.get(program_id)
            
            if program_info and program_info.get('variable_aware'):
                result['variable_aware'] = True
                result['variable_bindings'] = program_info.get('variable_bindings', {})
                
                # Get current variable values if possible
                program = program_info.get('program')
                if program and hasattr(program, 'get_bindings'):
                    current_values = {}
                    for attr, var_name in program.get_bindings().items():
                        if hasattr(program, attr):
                            current_values[attr] = getattr(program, attr)
                    result['current_values'] = current_values
        
        return result
    
    def update_variable_bindings(self, args):
        """
        Update variable bindings for a program.
        
        Args:
            id: Program ID
            bindings: Dict of attribute -> variable_name mappings
            unbind: List of attributes to unbind
        """
        if not self.variable_aware_enabled:
            return {"error": "Variable-aware features not available"}
        
        program_id = args.get('id')
        bindings = args.get('bindings', {})
        unbind = args.get('unbind', [])
        
        # Get program
        if self.mode == "pool-worker":
            program_info = self._get_program_from_session(args.get('session_id'), program_id)
        else:
            program_info = self.programs.get(program_id)
        
        if not program_info:
            return {"error": f"Program not found: {program_id}"}
        
        if not program_info.get('variable_aware'):
            return {"error": "Program is not variable-aware"}
        
        program = program_info['program']
        
        try:
            # Unbind specified attributes
            for attr in unbind:
                program.unbind_variable(attr)
            
            # Add new bindings
            for attr, var_name in bindings.items():
                program.bind_variable(attr, var_name)
            
            # Update stored bindings
            program_info['variable_bindings'] = program.get_bindings()
            
            return {
                "status": "updated",
                "bindings": program.get_bindings()
            }
            
        except Exception as e:
            return {"error": str(e)}
    
    def cleanup(self):
        """Clean up session contexts on shutdown."""
        super().cleanup()
        
        # Close all session contexts
        for ctx in self._session_contexts.values():
            try:
                ctx.close()
            except:
                pass
        
        self._session_contexts.clear()


# Import time for the enhanced functions
import time

# Re-export the debug_log function from original
from dspy_bridge import debug_log


def create_enhanced_bridge(mode="standalone", worker_id=None):
    """
    Factory function to create an enhanced DSPy bridge.
    
    This is the main entry point for creating a bridge with
    variable-aware support.
    """
    return EnhancedDSPyBridge(mode=mode, worker_id=worker_id)


# Example usage and testing
if __name__ == "__main__":
    # Test variable-aware bridge
    bridge = create_enhanced_bridge()
    
    # Create a variable-aware program
    result = bridge.create_program({
        'id': 'test_program',
        'session_id': 'test_session',
        'variable_aware': True,
        'signature': {
            'inputs': [{'name': 'question', 'type': 'string'}],
            'outputs': [{'name': 'answer', 'type': 'string'}]
        },
        'variable_bindings': {
            'temperature': 'llm_temperature',
            'max_tokens': 'max_generation_tokens'
        }
    })
    
    print("Program creation result:", result)
    
    # Execute with automatic variable sync
    if 'error' not in result:
        exec_result = bridge.execute_program({
            'id': 'test_program',
            'session_id': 'test_session',
            'inputs': {'question': 'What is DSPy?'}
        })
        
        print("Execution result:", exec_result)