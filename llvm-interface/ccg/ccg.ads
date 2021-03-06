------------------------------------------------------------------------------
--                              C C G                                       --
--                                                                          --
--                     Copyright (C) 2020, AdaCore                          --
--                                                                          --
-- This is free software;  you can redistribute it  and/or modify it  under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public  License  distributed  with  this  software;   see  file --
-- COPYING3.  If not, go to http://www.gnu.org/licenses for a complete copy --
-- of the license.                                                          --
------------------------------------------------------------------------------

with Interfaces.C;

with LLVM.Types; use LLVM.Types;

with Einfo; use Einfo;
with Namet; use Namet;
with Types; use Types;

with GNATLLVM; use GNATLLVM;

package CCG is

   subtype unsigned is Interfaces.C.unsigned;

   --  This package and its children generate C code from the LLVM IR
   --  generated by GNAT LLLVM.

   procedure Initialize_C_Writing;
   --  Do any initialization needed to write C.  This is always called after
   --  we've obtained target parameters.

   procedure Write_C_Code (Module : Module_T);
   --  The main procedure, which generates C code from the LLVM IR

   procedure C_Set_Field_Name_Info
     (TE          : Entity_Id;
      Idx         : Nat;
      Name        : Name_Id := No_Name;
      Is_Padding  : Boolean := False;
      Is_Bitfield : Boolean := False)
     with Pre => Is_Type (TE);
   --  Say what field Idx in the next struct is used for.  This is in
   --  the processing of TE.

   procedure C_Set_Struct (TE : Entity_Id; T : Type_T)
     with Pre => Is_Type (TE) and then Present (T), Inline;
   --  Indicate that the previous calls to Set_Field_Name_Info for TE
   --  were for LLVM struct type T.
   --  Define the sizes of all the basic C types.

   procedure C_Set_Is_Unsigned (V : Value_T)
     with Pre => Present (V), Inline;
   --  Indicate that V has an unsigned type.

   procedure Error_Msg (Msg : String);
   --  Post an error message via the GNAT errout mechanism.
   --  ??? For now, default to the First_Source_Ptr sloc. Will hopefully use a
   --  better source location in the future when we keep track of them for e.g.
   --  generating #line information.

   Char_Size      : Pos;
   Short_Size     : Pos;
   Int_Size       : Pos;
   Long_Size      : Pos;
   Long_Long_Size : Pos;

end CCG;
