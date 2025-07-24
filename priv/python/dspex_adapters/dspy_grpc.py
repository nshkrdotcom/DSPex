"""
DSPy gRPC Adapter for Snakepit v0.4.1

This adapter provides gRPC-based DSPy operations for DSPex integration.
Refactored to follow Snakepit v0.4.1 patterns with proper tool registration
and session management.
"""

import os
import json
import logging
import traceback
import inspect
import uuid
from typing import Dict, Any, Optional, List

# Import from snakepit_bridge - this will be available in the Python path
from snakepit_bridge import SessionContext
from snakepit_bridge.base_adapter import BaseAdapter, tool

logger = logging.getLogger(__name__)

# Try to import DSPy
try:
    import dspy
    DSPY_AVAILABLE = True
except ImportError:
    DSPY_AVAILABLE = False
    logger.warning("DSPy not available. Some functionality will be limited.")

# Module-level storage for persistence across adapter instances
_MODULE_STORAGE = {}


class DSPyGRPCHandler(BaseAdapter):
    """gRPC adapter for DSPy operations in DSPex, compatible with Snakepit v0.4.1"""
    
    def __init__(self):
        super().__init__()
        self.session_context = None
        
    def set_session_context(self, context: SessionContext):
        """Set the session context for variable access"""
        self.session_context = context
        
    @tool(description="Check DSPy availability and version")
    def check_dspy(self) -> Dict[str, Any]:
        """Check if DSPy is available and return version info"""
        if not DSPY_AVAILABLE:
            return {"available": False, "error": "DSPy not installed"}
            
        try:
            version = getattr(dspy, '__version__', 'unknown')
            return {
                "available": True,
                "version": version,
                "modules": dir(dspy)
            }
        except Exception as e:
            return {"available": False, "error": str(e)}
    
    @tool(description="Configure DSPy with a language model")
    def configure_lm(self, model_type: str, **kwargs) -> Dict[str, Any]:
        """Configure DSPy with a language model"""
        if not DSPY_AVAILABLE:
            return {"success": False, "error": "DSPy not available"}
            
        try:
            # Handle different model types
            if model_type == "openai":
                from dspy import OpenAI
                api_key = kwargs.get('api_key', os.getenv('OPENAI_API_KEY'))
                model = kwargs.get('model', 'gpt-3.5-turbo')
                lm = OpenAI(model=model, api_key=api_key)
            elif model_type == "anthropic":
                from dspy import Claude
                api_key = kwargs.get('api_key', os.getenv('ANTHROPIC_API_KEY'))
                model = kwargs.get('model', 'claude-3-sonnet-20240229')
                lm = Claude(model=model, api_key=api_key)
            elif model_type == "gemini":
                # Handle Gemini configuration using LiteLLM through DSPy
                api_key = kwargs.get('api_key', os.getenv('GOOGLE_API_KEY') or os.getenv('GEMINI_API_KEY'))
                model = kwargs.get('model', 'gemini-pro')
                
                if not api_key:
                    return {"success": False, "error": "No Gemini API key found. Set GOOGLE_API_KEY or GEMINI_API_KEY environment variable."}
                
                # Use DSPy's LM with LiteLLM for Gemini
                from dspy import LM
                lm = LM(f"gemini/{model}", api_key=api_key)
                
                # Configure DSPy to use this LM
                dspy.configure(lm=lm)
                
                # Store the LM for later use
                _MODULE_STORAGE['default_lm'] = lm
                
                return {"success": True, "model_type": model_type, "model": model}
            else:
                return {"success": False, "error": f"Unknown model type: {model_type}"}
                
            # Configure DSPy (for non-Gemini models)
            dspy.configure(lm=lm)
            
            # Store the LM for later use
            _MODULE_STORAGE['default_lm'] = lm
            
            return {"success": True, "model_type": model_type}
            
        except Exception as e:
            logger.error(f"Error configuring LM: {e}")
            return {"success": False, "error": str(e)}
    
    @tool(description="Create a DSPy signature from specification")
    def create_signature(self, name: str, inputs: List[Dict], outputs: List[Dict], 
                        docstring: Optional[str] = None) -> Dict[str, Any]:
        """Create a DSPy signature"""
        if not DSPY_AVAILABLE:
            return {"success": False, "error": "DSPy not available"}
            
        try:
            # Build signature string
            input_str = ", ".join([f"{field['name']}: {field.get('type', 'str')}" 
                                  for field in inputs])
            output_str = ", ".join([f"{field['name']}: {field.get('type', 'str')}" 
                                   for field in outputs])
            signature_str = f"{input_str} -> {output_str}"
            
            # Create signature class
            class_attrs = {'__doc__': docstring or f"Signature for {name}"}
            
            # Add input fields
            for field in inputs:
                field_desc = field.get('description', '')
                class_attrs[field['name']] = dspy.InputField(desc=field_desc)
                
            # Add output fields  
            for field in outputs:
                field_desc = field.get('description', '')
                class_attrs[field['name']] = dspy.OutputField(desc=field_desc)
                
            # Create signature class
            signature_class = type(name, (dspy.Signature,), class_attrs)
            
            # Store it
            _MODULE_STORAGE[f"signature_{name}"] = signature_class
            
            return {
                "success": True,
                "name": name,
                "signature_string": signature_str
            }
            
        except Exception as e:
            logger.error(f"Error creating signature: {e}")
            return {"success": False, "error": str(e)}
    
    @tool(description="Create a DSPy program")
    def create_program(self, name: str, program_type: str, signature_name: str,
                      **kwargs) -> Dict[str, Any]:
        """Create a DSPy program"""
        if not DSPY_AVAILABLE:
            return {"success": False, "error": "DSPy not available"}
            
        try:
            # Get signature
            signature = _MODULE_STORAGE.get(f"signature_{signature_name}")
            if not signature:
                # Try simple string signature
                signature = signature_name
                
            # Create program based on type
            if program_type == "predict":
                program = dspy.Predict(signature)
            elif program_type == "chain_of_thought":
                program = dspy.ChainOfThought(signature)
            elif program_type == "react":
                program = dspy.ReAct(signature)
            elif program_type == "program_of_thought":
                program = dspy.ProgramOfThought(signature)
            else:
                return {"success": False, "error": f"Unknown program type: {program_type}"}
                
            # Store program
            _MODULE_STORAGE[name] = program
            
            return {
                "success": True,
                "name": name,
                "type": program_type
            }
            
        except Exception as e:
            logger.error(f"Error creating program: {e}")
            return {"success": False, "error": str(e)}
    
    @tool(description="Execute a DSPy program")
    def execute_program(self, name: str, inputs: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a DSPy program with given inputs"""
        if not DSPY_AVAILABLE:
            return {"success": False, "error": "DSPy not available"}
            
        try:
            program = _MODULE_STORAGE.get(name)
            if not program:
                return {"success": False, "error": f"Program not found: {name}"}
            
            # Handle inputs - ensure it's a dictionary
            if isinstance(inputs, str):
                try:
                    inputs = json.loads(inputs)
                except json.JSONDecodeError:
                    return {"success": False, "error": f"Invalid inputs format: {inputs}"}
            elif not isinstance(inputs, dict):
                return {"success": False, "error": f"Inputs must be a dictionary, got {type(inputs)}: {inputs}"}
            
            logger.info(f"Executing program {name} with inputs: {inputs}")
            
            # Check if DSPy is properly configured
            if not hasattr(dspy.settings, 'lm') or dspy.settings.lm is None:
                return {"success": False, "error": "DSPy language model not configured. Call configure_lm first."}
                
            # Execute program
            result = program(**inputs)
            
            # Convert result to dict
            if hasattr(result, 'toDict'):
                output = result.toDict()
            else:
                # Extract non-private attributes
                output = {k: v for k, v in result.__dict__.items() 
                         if not k.startswith('_')}
                         
            return {
                "success": True,
                "result": output
            }
            
        except Exception as e:
            logger.error(f"Error executing program: {e}")
            return {"success": False, "error": str(e), "traceback": traceback.format_exc()}
    
    @tool(description="Store an object for later use")
    def store_object(self, name: str, object_type: str, data: Any) -> Dict[str, Any]:
        """Store an object in the session"""
        try:
            _MODULE_STORAGE[name] = data
            return {"success": True, "name": name}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    @tool(description="Retrieve a stored object")
    def retrieve_object(self, name: str) -> Dict[str, Any]:
        """Retrieve a stored object"""
        try:
            obj = _MODULE_STORAGE.get(name)
            if obj:
                # Try to serialize the object info
                return {
                    "success": True,
                    "name": name,
                    "type": type(obj).__name__,
                    "info": str(obj)
                }
            else:
                return {"success": False, "error": f"Object not found: {name}"}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    @tool(description="List stored objects")
    def list_stored_objects(self) -> Dict[str, Any]:
        """List all stored objects"""
        try:
            objects = []
            for name, obj in _MODULE_STORAGE.items():
                objects.append({
                    "name": name,
                    "type": type(obj).__name__
                })
            return {"success": True, "objects": objects}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    @tool(description="Get current DSPy settings")
    def get_settings(self) -> Dict[str, Any]:
        """Get current DSPy settings"""
        if not DSPY_AVAILABLE:
            return {"error": "DSPy not available"}
        
        try:
            settings = dspy.settings
            settings_dict = {}
            
            # Just get the core settings attributes we care about
            core_attrs = ['lm', 'rm', 'trace', 'explain', 'demonstrate', 'backoff_time', 
                        'branch_idx', 'trace_settings', 'force_rerun', 'compiling']
            
            for attr in core_attrs:
                try:
                    value = getattr(settings, attr, None)
                    
                    # Convert complex objects to string representation
                    if value is None:
                        settings_dict[attr] = None
                    elif isinstance(value, (str, int, float, bool)):
                        settings_dict[attr] = value
                    elif isinstance(value, (list, tuple)):
                        # Convert list items - check each item carefully
                        safe_list = []
                        for item in value:
                            if item is None:
                                safe_list.append(None)
                            elif isinstance(item, (str, int, float, bool)):
                                safe_list.append(item)
                            elif hasattr(item, '__module__'):
                                # Complex object - convert to string
                                safe_list.append(str(item))
                            else:
                                safe_list.append(str(item))
                        settings_dict[attr] = safe_list
                    elif isinstance(value, dict):
                        # Convert dict values - check each value carefully
                        safe_dict = {}
                        for k, v in value.items():
                            if v is None:
                                safe_dict[str(k)] = None
                            elif isinstance(v, (str, int, float, bool)):
                                safe_dict[str(k)] = v
                            elif hasattr(v, '__module__'):
                                # Complex object - convert to string
                                safe_dict[str(k)] = str(v)
                            else:
                                safe_dict[str(k)] = str(v)
                        settings_dict[attr] = safe_dict
                    else:
                        # Complex object - convert to string
                        settings_dict[attr] = str(value)
                except Exception as e:
                    logger.warning(f"Could not serialize settings.{attr}: {e}")
                    settings_dict[attr] = f"<{type(value).__name__} object>" if 'value' in locals() else None
                    
            return settings_dict
            
        except Exception as e:
            logger.error(f"Error getting settings: {e}")
            # Return minimal settings on error
            return {"error": str(e), "lm": None, "rm": None}
    
    @tool(description="Get DSPy statistics")
    def get_stats(self) -> Dict[str, Any]:
        """Get statistics about DSPy usage"""
        try:
            # Count DSPy objects in storage
            programs = [k for k in _MODULE_STORAGE.keys() if not k.startswith('signature_')]
            stats = {
                "dspy_available": DSPY_AVAILABLE,
                "programs_count": len(programs),
                "stored_objects_count": len(_MODULE_STORAGE),
                "programs": programs,
                "has_lm": 'default_lm' in _MODULE_STORAGE
            }
            
            if DSPY_AVAILABLE:
                # Add DSPy specific stats
                try:
                    stats["dspy_version"] = getattr(dspy, '__version__', 'unknown')
                    stats["has_configured_lm"] = hasattr(dspy.settings, 'lm') and dspy.settings.lm is not None
                except:
                    pass
                    
            return {"success": True, "stats": stats}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    @tool(description="Health check and ping")
    def ping(self) -> Dict[str, Any]:
        """Health check"""
        programs = [k for k in _MODULE_STORAGE.keys() if not k.startswith('signature_')]
        return {
            "status": "ok",
            "dspy_available": DSPY_AVAILABLE,
            "programs_count": len(programs),
            "stored_objects_count": len(_MODULE_STORAGE)
        }
    
    @tool(description="List all programs")
    def list_programs(self) -> Dict[str, Any]:
        """List all programs"""
        programs = [k for k in _MODULE_STORAGE.keys() if not k.startswith('signature_') and not k == 'default_lm']
        return {"programs": programs}
    
    @tool(description="Delete a program")
    def delete_program(self, name: str) -> Dict[str, Any]:
        """Delete a program"""
        if name in _MODULE_STORAGE:
            del _MODULE_STORAGE[name]
            return {"success": True}
        return {"success": False, "error": f"Program not found: {name}"}
    
    @tool(description="Reset all state")
    def reset_state(self) -> Dict[str, Any]:
        """Reset all state"""
        _MODULE_STORAGE.clear()
        return {"status": "reset"}
    
    @tool(description="Universal DSPy function caller with introspection")
    def call_dspy(self, module_path: str, function_name: str, args: List = None, kwargs: Dict = None) -> Dict[str, Any]:
        """
        Universal DSPy caller that can invoke any DSPy class or method.
        
        Examples:
        - Constructor: call_dspy("dspy.Predict", "__init__", [], {"signature": "question -> answer"})  
        - Method: call_dspy("stored.predict_123", "__call__", [], {"question": "What is DSPy?"})
        - Function: call_dspy("dspy.settings", "configure", [], {"lm": lm_instance})
        
        Returns:
        - Constructor: {"success": True, "instance_id": "predict_abc123", "type": "constructor"}
        - Method: {"success": True, "result": {...}, "type": "method"}  
        - Error: {"success": False, "error": "...", "traceback": "..."}
        """
        if not DSPY_AVAILABLE:
            return {"success": False, "error": "DSPy not available"}
            
        try:
            args = args or []
            kwargs = kwargs or {}
            
            # Parse kwargs if it's a JSON string (common due to Snakepit serialization)
            if isinstance(kwargs, str):
                try:
                    kwargs = json.loads(kwargs)
                except json.JSONDecodeError as e:
                    logger.warning(f"Failed to parse kwargs JSON: {e}, using empty dict")
                    kwargs = {}
            elif not isinstance(kwargs, dict):
                logger.warning(f"kwargs is not a dict or string (type: {type(kwargs)}), resetting to empty dict")
                kwargs = {}
            
            # Handle stored references (stored.instance_id)
            if module_path.startswith("stored."):
                instance_id = module_path[7:]  # Remove "stored." prefix
                target_obj = _MODULE_STORAGE.get(instance_id)
                if not target_obj:
                    return {"success": False, "error": f"Stored object not found: {instance_id}"}
                
                # Get the method/attribute
                if hasattr(target_obj, function_name):
                    func = getattr(target_obj, function_name)
                    if callable(func):
                        # Execute the method directly without signature validation
                        # (DSPy methods can be complex and signature validation may fail)
                        try:
                            result = func(*args, **kwargs)
                            return {
                                "success": True, 
                                "result": self._serialize_result(result), 
                                "type": "method"
                            }
                        except Exception as e:
                            return {"success": False, "error": f"Method execution failed: {e}"}
                    else:
                        return {"success": False, "error": f"'{function_name}' is not callable"}
                else:
                    return {"success": False, "error": f"Method '{function_name}' not found on stored object"}
            
            # Handle regular module paths (dspy.Predict, etc.)
            module_parts = module_path.split('.')
            if len(module_parts) < 2:
                return {"success": False, "error": f"Invalid module path: {module_path}"}
            
            # Import the module
            try:
                module_name = '.'.join(module_parts[:-1])
                class_name = module_parts[-1]
                module = __import__(module_name, fromlist=[class_name])
                target_class_or_func = getattr(module, class_name)
            except (ImportError, AttributeError) as e:
                return {"success": False, "error": f"Could not import {module_path}: {e}"}
            
            # Handle constructor calls
            if function_name == "__init__":
                try:
                    # Special handling for common DSPy classes that expect signature as first positional arg
                    if class_name in ['Predict', 'ChainOfThought', 'ReAct', 'ProgramOfThought'] and 'signature' in kwargs:
                        # Move signature from kwargs to first positional argument
                        signature = kwargs.pop('signature')
                        args = [signature] + list(args)
                    
                    # Create the instance
                    instance = target_class_or_func(*args, **kwargs)
                    instance_id = f"{class_name.lower()}_{hash(str(instance)) % 1000000:06d}"
                    _MODULE_STORAGE[instance_id] = instance
                    
                    return {
                        "success": True, 
                        "instance_id": instance_id, 
                        "type": "constructor",
                        "class_name": class_name
                    }
                        
                except Exception as e:
                    return {"success": False, "error": f"Constructor creation failed: {e}"}
                
                
            
            # Handle method calls on class (not instance)
            elif hasattr(target_class_or_func, function_name):
                func = getattr(target_class_or_func, function_name)
                if callable(func):
                    try:
                        result = func(*args, **kwargs)
                        return {
                            "success": True, 
                            "result": self._serialize_result(result), 
                            "type": "static_method"
                        }
                    except Exception as e:
                        return {"success": False, "error": f"Static method execution failed: {e}"}
                else:
                    return {"success": False, "error": f"'{function_name}' is not callable"}
            
            # Handle direct function call (when target is the function itself)
            elif callable(target_class_or_func):
                try:
                    result = target_class_or_func(*args, **kwargs)
                    return {
                        "success": True, 
                        "result": self._serialize_result(result), 
                        "type": "function"
                    }
                except Exception as e:
                    return {"success": False, "error": f"Function execution failed: {e}"}
            
            else:
                return {"success": False, "error": f"'{function_name}' not found on {module_path}"}
                
        except Exception as e:
            logger.error(f"call_dspy failed: {e}", exc_info=True)
            return {
                "success": False, 
                "error": str(e),
                "traceback": traceback.format_exc(),
                "module_path": module_path,
                "function_name": function_name
            }
    
    def _serialize_result(self, result):
        """Convert Python objects to JSON-serializable format"""
        try:
            # Handle DSPy-specific result types
            if hasattr(result, 'toDict'):
                return result.toDict()
            elif hasattr(result, '__dict__'):
                # Extract non-private attributes
                serialized = {}
                for k, v in result.__dict__.items():
                    if not k.startswith('_'):
                        try:
                            # Try to serialize the value
                            if isinstance(v, (str, int, float, bool, type(None))):
                                serialized[k] = v
                            elif isinstance(v, (list, tuple)):
                                serialized[k] = [self._serialize_value(item) for item in v]
                            elif isinstance(v, dict):
                                serialized[k] = {str(key): self._serialize_value(val) for key, val in v.items()}
                            else:
                                serialized[k] = str(v)
                        except:
                            serialized[k] = f"<{type(v).__name__} object>"
                return serialized
            elif isinstance(result, (list, tuple)):
                return [self._serialize_value(item) for item in result]
            elif isinstance(result, dict):
                return {str(k): self._serialize_value(v) for k, v in result.items()}
            else:
                return str(result)
        except Exception as e:
            logger.warning(f"Failed to serialize result: {e}")
            return str(result)
    
    def _serialize_value(self, value):
        """Helper to serialize individual values"""
        if isinstance(value, (str, int, float, bool, type(None))):
            return value
        elif hasattr(value, 'toDict'):
            return value.toDict()
        else:
            return str(value)
    
    @tool(description="Discover DSPy module schema with introspection")
    def discover_dspy_schema(self, module_path: str = "dspy") -> Dict[str, Any]:
        """
        Auto-discover available classes, methods, and signatures in DSPy modules.
        
        Returns complete schema including:
        - Class definitions and docstrings
        - Method signatures and parameter types  
        - Constructor requirements
        - Inheritance hierarchies
        
        Example output:
        {
          "success": True,
          "schema": {
            "Predict": {
              "type": "class",
              "docstring": "Basic predictor module...",
              "methods": {
                "__init__": {
                  "signature": "(self, signature, **kwargs)",
                  "parameters": ["signature"],
                  "docstring": "Initialize predictor with signature"
                },
                "__call__": {
                  "signature": "(self, **kwargs)",
                  "parameters": [],
                  "docstring": "Execute prediction"
                }
              }
            }
          }
        }
        """
        if not DSPY_AVAILABLE:
            return {"success": False, "error": "DSPy not available"}
            
        try:
            # Import the target module
            try:
                module = __import__(module_path)
                # For nested imports like dspy.retrievers, we need to get the right submodule
                parts = module_path.split('.')
                for part in parts[1:]:
                    module = getattr(module, part)
            except (ImportError, AttributeError) as e:
                return {"success": False, "error": f"Could not import {module_path}: {e}"}
            
            schema = {}
            
            # Discover all classes and functions in the module
            for name in dir(module):
                if name.startswith('_'):
                    continue
                    
                try:
                    obj = getattr(module, name)
                    
                    if inspect.isclass(obj):
                        # This is a class - discover its methods
                        class_schema = {
                            "type": "class",
                            "docstring": inspect.getdoc(obj) or f"DSPy {name} class",
                            "methods": {},
                            "module": obj.__module__ if hasattr(obj, '__module__') else module_path
                        }
                        
                        # Discover methods on this class
                        for method_name in dir(obj):
                            # Include important methods (including __init__ and __call__)
                            if (not method_name.startswith('_') or 
                                method_name in ['__init__', '__call__', '__str__', '__repr__']):
                                try:
                                    method = getattr(obj, method_name)
                                    if callable(method):
                                        # Get method signature
                                        try:
                                            sig = inspect.signature(method)
                                            parameters = []
                                            for param_name, param in sig.parameters.items():
                                                if param_name != 'self':  # Skip 'self' parameter
                                                    param_info = {"name": param_name}
                                                    if param.default != inspect.Parameter.empty:
                                                        param_info["default"] = str(param.default)
                                                    if param.annotation != inspect.Parameter.empty:
                                                        param_info["type"] = str(param.annotation)
                                                    parameters.append(param_info)
                                            
                                            class_schema["methods"][method_name] = {
                                                "signature": str(sig),
                                                "parameters": parameters,
                                                "docstring": inspect.getdoc(method) or f"{name}.{method_name} method"
                                            }
                                        except (ValueError, TypeError):
                                            # Some methods might not have inspectable signatures
                                            class_schema["methods"][method_name] = {
                                                "signature": "(*args, **kwargs)",
                                                "parameters": [],
                                                "docstring": inspect.getdoc(method) or f"{name}.{method_name} method"
                                            }
                                except:
                                    # Skip methods that can't be introspected
                                    continue
                        
                        schema[name] = class_schema
                        
                    elif callable(obj) and not inspect.isbuiltin(obj):
                        # This is a function
                        try:
                            sig = inspect.signature(obj)
                            parameters = []
                            for param_name, param in sig.parameters.items():
                                param_info = {"name": param_name}
                                if param.default != inspect.Parameter.empty:
                                    param_info["default"] = str(param.default)
                                if param.annotation != inspect.Parameter.empty:
                                    param_info["type"] = str(param.annotation)
                                parameters.append(param_info)
                            
                            schema[name] = {
                                "type": "function",
                                "signature": str(sig),
                                "parameters": parameters,
                                "docstring": inspect.getdoc(obj) or f"DSPy {name} function",
                                "module": obj.__module__ if hasattr(obj, '__module__') else module_path
                            }
                        except:
                            # Skip functions that can't be introspected
                            continue
                except:
                    # Skip any objects that cause errors during introspection
                    continue
            
            return {
                "success": True, 
                "schema": schema,
                "module_path": module_path,
                "discovered_count": len(schema)
            }
            
        except Exception as e:
            logger.error(f"discover_dspy_schema failed: {e}", exc_info=True)
            return {
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc(),
                "module_path": module_path
            }
    
    # Legacy execute_tool method for backward compatibility with gRPC server
    def execute_tool(self, tool_name: str, arguments: Dict[str, Any], context) -> Any:
        """Execute a tool by name with given arguments (legacy support)."""
        self.session_context = context
        
        # Map tool names to methods
        tool_methods = {
            "check_dspy": self.check_dspy,
            "configure_lm": lambda: self.configure_lm(**arguments),
            "create_signature": lambda: self.create_signature(**arguments),
            "create_program": lambda: self.create_program(**arguments),
            "execute_program": lambda: self.execute_program(**arguments),
            "store_object": lambda: self.store_object(**arguments),
            "retrieve_object": lambda: self.retrieve_object(**arguments),
            "list_stored_objects": self.list_stored_objects,
            "get_settings": self.get_settings,
            "get_stats": self.get_stats,
            "ping": self.ping,
            "list_programs": self.list_programs,
            "delete_program": lambda: self.delete_program(**arguments),
            "reset_state": self.reset_state,
            "call_dspy": lambda: self.call_dspy(**arguments),
            "discover_dspy_schema": lambda: self.discover_dspy_schema(**arguments)
        }
        
        if tool_name in tool_methods:
            return tool_methods[tool_name]()
        else:
            # Try the new tool system if available
            try:
                return self.call_tool(tool_name, **arguments)
            except AttributeError:
                raise ValueError(f"Unknown tool: {tool_name}")
