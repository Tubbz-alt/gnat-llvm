pragma Ada_2005;
pragma Style_Checks (Off);

pragma Warnings (Off); with Interfaces.C; use Interfaces.C; pragma Warnings (On);
with System;

package LLVM.Types is

  --===-- llvm-c/Support.h - C Interface Types declarations ---------*- C -*-===*|*                                                                            *|
  --|
  --|*                     The LLVM Compiler Infrastructure                       *|
  --|*                                                                            *|
  --|* This file is distributed under the University of Illinois Open Source      *|
  --|* License. See LICENSE.TXT for details.                                      *|
  --|*                                                                            *|
  --|*===----------------------------------------------------------------------===*|
  --|*                                                                            *|
  --|* This file defines types used by the the C interface to LLVM.               *|
  --|*                                                                            *|
  --\*===----------------------------------------------------------------------=== 

  --*
  -- * @defgroup LLVMCSupportTypes Types and Enumerations
  -- *
  -- * @{
  --  

   subtype Bool_T is int;  -- llvm-6.0.0.src/include/llvm-c/Types.h:29

  -- Opaque types.  
  --*
  -- * LLVM uses a polymorphic type hierarchy which C cannot represent, therefore
  -- * parameters must be passed as base types. Despite the declared types, most
  -- * of the functions provided operate only on branches of the type hierarchy.
  -- * The declared parameter names are descriptive and specify which type is
  -- * required. Additionally, each type hierarchy is documented along with the
  -- * functions that operate upon it. For more detail, refer to LLVM's C++ code.
  -- * If in doubt, refer to Core.cpp, which performs parameter downcasts in the
  -- * form unwrap<RequiredType>(Param).
  --  

  --*
  -- * Used to pass regions of memory through LLVM interfaces.
  -- *
  -- * @see llvm::MemoryBuffer
  --  

   --  skipped empty struct LLVMOpaqueMemoryBuffer

   type Memory_Buffer_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:49

  --*
  -- * The top-level container for all LLVM global data. See the LLVMContext class.
  --  

   --  skipped empty struct LLVMOpaqueContext

   type Context_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:54

  --*
  -- * The top-level container for all other LLVM Intermediate Representation (IR)
  -- * objects.
  -- *
  -- * @see llvm::Module
  --  

   --  skipped empty struct LLVMOpaqueModule

   type Module_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:62

  --*
  -- * Each value in the LLVM IR has a type, an LLVMTypeRef.
  -- *
  -- * @see llvm::Type
  --  

   --  skipped empty struct LLVMOpaqueType

   type Type_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:69

  --*
  -- * Represents an individual value in LLVM IR.
  -- *
  -- * This models llvm::Value.
  --  

   --  skipped empty struct LLVMOpaqueValue

   type Value_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:76

  --*
  -- * Represents a basic block of instructions in LLVM IR.
  -- *
  -- * This models llvm::BasicBlock.
  --  

   --  skipped empty struct LLVMOpaqueBasicBlock

   type Basic_Block_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:83

  --*
  -- * Represents an LLVM Metadata.
  -- *
  -- * This models llvm::Metadata.
  --  

   --  skipped empty struct LLVMOpaqueMetadata

   type Metadata_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:90

  --*
  -- * Represents an LLVM basic block builder.
  -- *
  -- * This models llvm::IRBuilder.
  --  

   --  skipped empty struct LLVMOpaqueBuilder

   type Builder_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:97

  --*
  -- * Represents an LLVM debug info builder.
  -- *
  -- * This models llvm::DIBuilder.
  --  

   --  skipped empty struct LLVMOpaqueDIBuilder

   type DI_Builder_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:104

  --*
  -- * Interface used to provide a module to JIT or interpreter.
  -- * This is now just a synonym for llvm::Module, but we have to keep using the
  -- * different type to keep binary compatibility.
  --  

   --  skipped empty struct LLVMOpaqueModuleProvider

   type Module_Provider_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:111

  --* @see llvm::PassManagerBase  
   --  skipped empty struct LLVMOpaquePassManager

   type Pass_Manager_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:114

  --* @see llvm::PassRegistry  
   --  skipped empty struct LLVMOpaquePassRegistry

   type Pass_Registry_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:117

  --*
  -- * Used to get the users and usees of a Value.
  -- *
  -- * @see llvm::Use  

   --  skipped empty struct LLVMOpaqueUse

   type Use_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:123

  --*
  -- * Used to represent an attributes.
  -- *
  -- * @see llvm::Attribute
  --  

   --  skipped empty struct LLVMOpaqueAttributeRef

   type Attribute_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:130

  --*
  -- * @see llvm::DiagnosticInfo
  --  

   --  skipped empty struct LLVMOpaqueDiagnosticInfo

   type Diagnostic_Info_T is new System.Address;  -- llvm-6.0.0.src/include/llvm-c/Types.h:135

  --*
  -- * @}
  --  

end LLVM.Types;

