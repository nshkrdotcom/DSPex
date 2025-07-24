"""
DSPy gRPC Adapter for Snakepit

This adapter provides gRPC-based DSPy operations for DSPex integration.
It replaces the old JSON-based protocol with efficient gRPC communication.
"""

import os
import json
import logging
import traceback
from typing import Dict, Any, Optional, List
from dataclasses import dataclass

from ..base_adapter import BaseAdapter, tool
from ..session_context import SessionContext
from ..serialization import TypeSerializer

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
    """gRPC adapter for DSPy operations in DSPex"""
    
    def __init__(self):
        super().__init__()
        self.session_context = None
        
    def set_session_context(self, context: SessionContext):
        """Set the session context for variable access"""
        self.session_context = context
        # Note: The session context may have issues with async gRPC calls
        # The errors about UnaryUnaryCall objects are from snakepit's
        # Python bridge using async stubs in sync methods
        
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
                # Handle Gemini configuration
                import google.generativeai as genai
                api_key = kwargs.get('api_key', os.getenv('GOOGLE_API_KEY'))
                genai.configure(api_key=api_key)
                # Note: DSPy might need a wrapper for Gemini
                return {"success": True, "message": "Gemini configured (may need DSPy wrapper)"}
            else:
                return {"success": False, "error": f"Unknown model type: {model_type}"}
                
            # Configure DSPy
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
                field_type = self._get_dspy_field_type(field.get('type', 'str'))
                field_desc = field.get('description', '')
                class_attrs[field['name']] = dspy.InputField(desc=field_desc)
                
            # Add output fields  
            for field in outputs:
                field_type = self._get_dspy_field_type(field.get('type', 'str'))
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
    
    def _get_dspy_field_type(self, type_str: str):
        """Convert type string to DSPy field type"""
        # For now, DSPy mainly uses string types
        # This can be extended as DSPy adds more type support
        return str
    
    # Legacy execute_tool method for compatibility
    def execute_tool(self, tool_name: str, context: SessionContext, arguments: Optional[Dict[str, Any]] = None, **kwargs) -> Any:
        """Legacy tool execution method"""
        self.session_context = context
        # Handle both args and arguments parameters
        args = arguments or kwargs.get('args', {})
        
        # Handle Python.call style invocations
        if "." in tool_name or tool_name.startswith("dspy."):
            return self._handle_python_call(tool_name, args)
        
        # Map old commands to new tool methods
        command_map = {
            "call": lambda: self._handle_call_command(args),
            "check_dspy": self.check_dspy,
            "configure_lm": lambda: self.configure_lm(**args),
            "create_signature": lambda: self.create_signature(**args),
            "create_program": lambda: self.create_program(**args),
            "execute_program": lambda: self.execute_program(**args),
            "store": lambda: self.store_object(**args),
            "retrieve": lambda: self.retrieve_object(**args),
            "list_stored": self.list_stored_objects,
            "get_stats": self.get_stats,
            "get_settings": self.get_settings,  # Add this mapping
            "ping": lambda: self._ping(args),
            "list_programs": self._list_programs,
            "delete_program": lambda: self._delete_program(**args),
            "cleanup": lambda: self._cleanup(**args),
            "reset_state": self._reset_state
        }
        
        if tool_name in command_map:
            return command_map[tool_name]()
        else:
            raise ValueError(f"Unknown tool: {tool_name}")
    
    def _handle_call_command(self, args: Dict[str, Any]) -> Any:
        """Handle the 'call' command from Snakepit.Python.call"""
        target = args.get("target", "")
        kwargs = args.get("kwargs", {})
        store_as = args.get("store_as")
        
        # If kwargs is a string, try to parse it as JSON
        if isinstance(kwargs, str):
            try:
                kwargs = json.loads(kwargs)
            except json.JSONDecodeError:
                # If it's not valid JSON, leave it as is
                pass
        
        result = self._handle_python_call(target, kwargs)
        
        # If store_as is specified, store the actual result object
        if store_as:
            # Check if we have a result object to store
            if "_store_object" in result:
                _MODULE_STORAGE[store_as] = result["_store_object"]
                # Remove _store_object from result to avoid serialization issues
                del result["_store_object"]
                # Store metadata about the object
                result["stored_as"] = store_as
            elif "_metadata" in result and "result" in result:
                # Store the actual object from result
                _MODULE_STORAGE[store_as] = result["result"]
                # Return just the metadata
                return {"result": result["_metadata"], "stored_as": store_as}
            elif "result" in result:
                # Check if result is a DSPy object that needs special handling
                obj = result["result"]
                if hasattr(obj, '__module__') and obj.__module__ and 'dspy' in obj.__module__:
                    # Store the DSPy object and return metadata
                    _MODULE_STORAGE[store_as] = obj
                    return {"result": {"type": type(obj).__name__, "stored_as": store_as}}
                else:
                    # Simple result, just store it
                    _MODULE_STORAGE[store_as] = obj
            
        # If there's metadata, return that instead of the actual object for serialization
        if "_metadata" in result and "result" in result:
            # We have both metadata and an object - return just metadata
            return {"result": result["_metadata"]}
            
        return result
    
    def _handle_python_call(self, target: str, kwargs: Dict[str, Any]) -> Any:
        """Handle Python.call style invocations (e.g. 'dspy.__version__')"""
        logger.info(f"Handling Python.call for target: {target}")
        if not DSPY_AVAILABLE and target.startswith("dspy."):
            raise RuntimeError("DSPy not available")
            
        try:
            # Handle special cases
            if target == "dspy.__version__":
                return {"result": {"value": getattr(dspy, '__version__', 'unknown')}}
            elif target == "dspy.__name__":
                return {"result": {"value": "dspy"}}
            elif target == "dspy.settings":
                # Handle dspy.settings specially - return a dict representation
                try:
                    settings = dspy.settings
                    settings_dict = {}
                    
                    # Just get the core settings attributes we care about
                    core_attrs = ['lm', 'rm', 'trace', 'explain', 'demonstrate', 'backoff_time', 
                                'branch_idx', 'trace_settings', 'force_rerun', 'compiling']
                    
                    for attr in core_attrs:
                        try:
                            value = getattr(settings, attr, None)
                            logger.debug(f"Processing settings.{attr}: type={type(value).__name__ if value else 'None'}")
                            
                            # Convert complex objects to string representation
                            if value is None:
                                settings_dict[attr] = None
                            elif isinstance(value, (str, int, float, bool)):
                                settings_dict[attr] = value
                            elif isinstance(value, (list, tuple)):
                                # Convert list items to strings if they're DSPy objects
                                safe_list = []
                                for i, item in enumerate(value):
                                    logger.debug(f"  List item {i}: type={type(item).__name__}")
                                    # Check if it's a DSPy object
                                    if hasattr(item, '__module__'):
                                        module_name = str(getattr(item, '__module__', ''))
                                        if 'dspy' in module_name or module_name == '__main__':
                                            # Convert DSPy object to string
                                            safe_list.append(str(item))
                                        else:
                                            safe_list.append(item)
                                    else:
                                        safe_list.append(item)
                                settings_dict[attr] = safe_list
                            elif isinstance(value, dict):
                                # Convert dict values to strings if they're DSPy objects
                                safe_dict = {}
                                for k, v in value.items():
                                    logger.debug(f"  Dict key {k}: type={type(v).__name__}")
                                    if hasattr(v, '__module__'):
                                        module_name = str(getattr(v, '__module__', ''))
                                        if 'dspy' in module_name or module_name == '__main__':
                                            safe_dict[str(k)] = str(v)
                                        else:
                                            safe_dict[str(k)] = v
                                    else:
                                        safe_dict[str(k)] = v
                                settings_dict[attr] = safe_dict
                            else:
                                # Complex object - convert to string
                                logger.debug(f"  Converting complex object to string: {type(value).__name__}")
                                settings_dict[attr] = str(value)
                        except Exception as e:
                            logger.warning(f"Could not serialize settings.{attr}: {e}")
                            settings_dict[attr] = f"<{type(value).__name__} object>" if 'value' in locals() else None
                            
                    logger.info(f"Final settings_dict: {list(settings_dict.keys())}")
                    logger.info(f"Settings_dict types: {[(k, type(v).__name__) for k, v in settings_dict.items()]}")
                            
                    # Double-check that we don't have any complex objects
                    clean_dict = {}
                    for k, v in settings_dict.items():
                        if isinstance(v, (str, int, float, bool, type(None))):
                            clean_dict[k] = v
                        elif isinstance(v, (list, tuple)):
                            # Make sure all list items are serializable
                            clean_list = []
                            for item in v:
                                # Check if it's a basic type first
                                if item is None or isinstance(item, (str, int, float, bool)):
                                    clean_list.append(item)
                                else:
                                    # Complex object - convert to string
                                    clean_list.append(str(item))
                            clean_dict[k] = clean_list
                        elif isinstance(v, dict):
                            # Make sure all dict values are serializable
                            clean_subdict = {}
                            for dk, dv in v.items():
                                if hasattr(dv, '__module__'):
                                    clean_subdict[str(dk)] = str(dv)
                                else:
                                    clean_subdict[str(dk)] = dv
                            clean_dict[k] = clean_subdict
                        else:
                            clean_dict[k] = str(v)
                            
                    return {"result": clean_dict}
                    
                except Exception as e:
                    logger.error(f"Error handling dspy.settings: {e}")
                    # Return minimal settings on error
                    return {"result": {"error": str(e), "lm": None, "rm": None}}
            elif target.startswith("stored."):
                # Handle stored object access
                parts = target[7:].split(".", 1)  # Remove "stored." prefix
                obj_name = parts[0]
                obj = _MODULE_STORAGE.get(obj_name)
                if obj:
                    if len(parts) == 1:
                        return {"result": str(obj)}
                    elif parts[1] == "__call__":
                        # Execute the stored program
                        result = obj(**kwargs)
                        if hasattr(result, 'toDict'):
                            return {"result": result.toDict()}
                        else:
                            return {"result": {k: v for k, v in result.__dict__.items() 
                                             if not k.startswith('_')}}
                    else:
                        # Access attribute or call method
                        attr = getattr(obj, parts[1])
                        # Check if it's a callable (method)
                        if callable(attr):
                            # It's a method - call it with kwargs
                            logger.info(f"Calling method {parts[1]} on stored object {obj_name} with kwargs: {kwargs}")
                            # Resolve any stored references in kwargs
                            resolved_kwargs = {}
                            for k, v in kwargs.items():
                                if isinstance(v, str) and v.startswith("stored."):
                                    # Resolve stored reference
                                    stored_name = v[7:]  # Remove "stored." prefix
                                    stored_obj = _MODULE_STORAGE.get(stored_name)
                                    if stored_obj:
                                        resolved_kwargs[k] = stored_obj
                                    else:
                                        raise ValueError(f"Stored object not found: {stored_name}")
                                else:
                                    resolved_kwargs[k] = v
                            
                            result = attr(**resolved_kwargs)
                            # Handle the result based on what it is
                            if hasattr(result, '__module__') and result.__module__ and 'dspy' in result.__module__:
                                # It's a DSPy object - store it and return metadata
                                result_id = f"{obj_name}_{parts[1]}_result"
                                _MODULE_STORAGE[result_id] = result
                                return {"result": {"type": type(result).__name__, "stored_as": result_id}}
                            elif hasattr(result, 'toDict'):
                                return {"result": result.toDict()}
                            else:
                                return {"result": result}
                        else:
                            # It's a regular attribute
                            return {"result": attr}
                else:
                    raise ValueError(f"Stored object not found: {obj_name}")
            else:
                # General Python evaluation (be careful with this in production!)
                # Special handling for dspy.LM
                if target == "dspy.LM":
                    # dspy.LM constructor
                    logger.info(f"Creating dspy.LM with kwargs: {kwargs}")
                    logger.info(f"kwargs type: {type(kwargs)}, content: {kwargs}")
                    # Ensure kwargs is a dict
                    if not isinstance(kwargs, dict):
                        # If it's a string, try to parse it as JSON
                        if isinstance(kwargs, str):
                            try:
                                kwargs = json.loads(kwargs)
                                logger.info(f"Parsed kwargs from JSON: {kwargs}")
                            except json.JSONDecodeError:
                                raise TypeError(f"kwargs must be a dict or valid JSON string, got {type(kwargs)}: {kwargs}")
                        else:
                            raise TypeError(f"kwargs must be a dict, got {type(kwargs)}")
                    lm = dspy.LM(**kwargs)
                    # Return the actual LM object for storage, with metadata for serialization
                    return {"result": lm, "_metadata": {"type": "LM", "model": kwargs.get("model", "unknown")}}
                elif target == "dspy.configure":
                    # Handle dspy.configure - need to resolve stored references
                    if "lm" in kwargs and isinstance(kwargs["lm"], str) and kwargs["lm"].startswith("stored."):
                        # Resolve stored LM reference
                        lm_name = kwargs["lm"][7:]  # Remove "stored." prefix
                        lm = _MODULE_STORAGE.get(lm_name)
                        if lm:
                            kwargs["lm"] = lm
                    dspy.configure(**kwargs)
                    return {"result": {"status": "configured"}}
                elif target in ["dspy.Predict", "dspy.ChainOfThought", "dspy.ReAct", "dspy.ProgramOfThought"]:
                    # Handle DSPy module creation
                    parts = target.split(".")
                    module_class = getattr(dspy, parts[1])
                    module_instance = module_class(**kwargs)
                    # Return metadata for serialization, actual object will be stored
                    return {"result": module_instance, "_metadata": {"type": parts[1], "signature": kwargs.get("signature", "")}}
                elif target == "dspy.Example":
                    # Handle Example creation
                    logger.info(f"Creating dspy.Example with kwargs: {kwargs}")
                    example = dspy.Example(**kwargs)
                    logger.info(f"Created example: {type(example).__name__}")
                    # DSPy Example objects store data as attributes
                    # Extract all non-private attributes
                    example_dict = {}
                    for attr in dir(example):
                        if not attr.startswith('_') and not callable(getattr(example, attr, None)):
                            try:
                                value = getattr(example, attr)
                                example_dict[attr] = value
                            except:
                                pass
                    
                    # If no attributes found, use the kwargs
                    if not example_dict:
                        example_dict = kwargs
                        
                    logger.info(f"Example dict: {example_dict}")
                    # Return dict for serialization, but mark that we have an object to store
                    return {"result": example_dict, "_store_object": example}
                elif target == "dspy.datasets.Dataset":
                    # Handle Dataset creation
                    dataset = dspy.datasets.Dataset(**kwargs)
                    return {"result": {"type": "Dataset", "length": len(dataset)}, "_store_object": dataset}
                else:
                    # General case - handle simple attribute access
                    logger.info(f"General case for target: {target}")
                    parts = target.split(".")
                    obj = globals().get(parts[0])
                    if not obj and parts[0] == "dspy":
                        obj = dspy
                    for part in parts[1:]:
                        obj = getattr(obj, part)
                    if callable(obj):
                        logger.info(f"Calling {target} with kwargs: {kwargs}")
                        result = obj(**kwargs)
                        logger.info(f"Result type: {type(result).__name__}")
                        # Check if result is a DSPy object that can't be serialized
                        if hasattr(result, '__module__') and result.__module__.startswith('dspy'):
                            logger.info(f"Result is a DSPy object, returning with metadata")
                            return {"result": result, "_metadata": {"type": type(result).__name__}}
                        return {"result": result}
                    else:
                        logger.info(f"Returning attribute: {type(obj).__name__}")
                        # Check if it's a complex DSPy object that needs special handling
                        if hasattr(obj, '__module__') and obj.__module__.startswith('dspy'):
                            return {"result": str(obj)}
                        return {"result": obj}
        except Exception as e:
            logger.error(f"Error in Python.call for {target}: {e}")
            raise
    
    def _ping(self, args: Dict[str, Any]) -> Dict[str, Any]:
        """Health check"""
        programs = [k for k in _MODULE_STORAGE.keys() if not k.startswith('signature_')]
        return {
            "status": "ok",
            "dspy_available": DSPY_AVAILABLE,
            "programs_count": len(programs),
            "stored_objects_count": len(_MODULE_STORAGE)
        }
    
    def _list_programs(self) -> Dict[str, Any]:
        """List all programs"""
        programs = [k for k in _MODULE_STORAGE.keys() if not k.startswith('signature_') and not k == 'default_lm']
        return {"programs": programs}
    
    def _delete_program(self, name: str) -> Dict[str, Any]:
        """Delete a program"""
        if name in _MODULE_STORAGE:
            del _MODULE_STORAGE[name]
            return {"success": True}
        return {"success": False, "error": f"Program not found: {name}"}
    
    def _cleanup(self, **kwargs) -> Dict[str, Any]:
        """Cleanup resources"""
        # In gRPC mode, cleanup is handled by session management
        return {"status": "ok"}
    
    def _reset_state(self) -> Dict[str, Any]:
        """Reset all state"""
        _MODULE_STORAGE.clear()
        return {"status": "reset"}