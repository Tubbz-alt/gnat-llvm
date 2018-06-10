------------------------------------------------------------------------------
--                             G N A T - L L V M                            --
--                                                                          --
--                     Copyright (C) 2013-2018, AdaCore                     --
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

with Sem_Eval; use Sem_Eval;
with Stand;    use Stand;
with Table;    use Table;
with Uintp;    use Uintp;

with LLVM.Core;  use LLVM.Core;

with GNATLLVM.Compile;     use GNATLLVM.Compile;
with GNATLLVM.DebugInfo;   use GNATLLVM.DebugInfo;
with GNATLLVM.Environment; use GNATLLVM.Environment;
with GNATLLVM.Exprs;       use GNATLLVM.Exprs;
with GNATLLVM.Records;     use GNATLLVM.Records;
with GNATLLVM.Subprograms; use GNATLLVM.Subprograms;
with GNATLLVM.Utils;       use GNATLLVM.Utils;

package body GNATLLVM.Arrays is

   --  A bound of a constrained array can either be a compile-time
   --  constant, which we record as a Uint or some dynamic value that was
   --  known at the declaration of the type, which can include a refdrence
   --  to a discriminant.  We use the structures and table below to
   --  indicate which.  The value return by Get_Array_Info is the index
   --  into this table for the first index of a constrained array whose
   --  size isn't known at compile-time.  The remaining bounds are
   --  subsequent entries in the table.

   type One_Bound is record
      Cnst    : Uint;
      Value   : Node_Id;
      Dynamic : Boolean;
   end record
     --  Only one item can be specified and the specification of Value
     --  means that Dynamic must be true.  We might think that exactly one
     --  item must be specified, but that's not the case for an
     --  unconstrained array.
     with Predicate => ((if Cnst = No_Uint then 0 else 1) +
                        (if No (Value) then 0 else 1)) <= 1
                       and then (No (Value) or else Dynamic);

   type Index_Bounds is record
      Bound_Type    : Entity_Id;
      Bound_Subtype : Entity_Id;
      Low, High     : One_Bound;
   end record
     with Predicate => Is_Discrete_Type (Bound_Type)
                       and then Is_Discrete_Type (Bound_Subtype);

   package Array_Info is new Table.Table
     (Table_Component_Type => Index_Bounds,
      Table_Index_Type     => Nat,
      Table_Low_Bound      => 1,
      Table_Initial        => 1024,
      Table_Increment      => 100,
      Table_Name           => "Array_Info_Table");
   --  Table of representation of arrays indexes

   function Type_For_Get_Bound
     (TE : Entity_Id; V : GL_Value) return Entity_Id
     with Pre  => Is_Array_Type (TE),
          Post => Is_Array_Type (Type_For_Get_Bound'Result);
   --  Get the best type to use to search for a bound of an arrray

   function Contains_Discriminant (N : Node_Id) return Entity_Id;
   --  Return the discrminant if N contains a reference to a discriminant

   function Build_One_Bound
     (N : Node_Id; Unconstrained : Boolean) return One_Bound
     with Pre => Present (N);
   --  Helper function to build a One_Bound object from N

   function Create_String_Literal_Type
     (TE : Entity_Id; Comp_Typ : Type_T) return Type_T
     with Pre  => Ekind (TE) = E_String_Literal_Subtype
                  and then Present (Comp_Typ),
          Post => (Get_Type_Kind (Create_String_Literal_Type'Result) =
                     Array_Type_Kind);
   --  Helper function to create type for string literals

   function Bound_Complexity
     (B : One_Bound; For_Type : Boolean) return Nat is
      (if B.Cnst /= No_Uint then 0 elsif Present (B.Value) then 1
       elsif For_Type then 1 else 2);

   function Get_GEP_Safe_Type (V : GL_Value) return Entity_Id
     with Pre  => not Is_Reference (V),
          Post => Is_Integer_Type (Get_GEP_Safe_Type'Result);
   --  GEP treats array indices as signed values.  If the type is unsigned
   --  (including Boolean; see C55C02B), it will sign-extend rather than
   --  zero-extend the value.  So if this type is smaller than the size of
   --  a pointer and is unsigned, we must return a wider type.

   ---------------------
   -- Build_One_Bound --
   ---------------------

   function Build_One_Bound
     (N : Node_Id; Unconstrained : Boolean) return One_Bound is

   begin
      if Unconstrained then
         return (Cnst => No_Uint, Value => Empty, Dynamic => True);
      elsif Compile_Time_Known_Value (N) then
         return (Cnst => Expr_Value (N), Value => Empty,
                 Dynamic => not UI_Is_In_Int_Range (Expr_Value (N)));
      else
         return (Cnst => No_Uint, Value => N, Dynamic => True);
      end if;

   end Build_One_Bound;

   ------------------------
   -- Type_For_Get_Bound --
   ------------------------

   function Type_For_Get_Bound
     (TE : Entity_Id; V : GL_Value) return Entity_Id
   is
      V_Type : constant Entity_Id :=
        (if No (V) then Empty else Related_Type (V));

   begin
      --  If only TE is around, use it.  Likewise if V_Type is not an
      --  array type or not related to TE.  Otherwise, use the type
      --  that's constrained, preferring V's type, but only if
      --  TE is unconstrained.

      if No (V_Type) or else not Is_Array_Type (V_Type)
        or else (Ultimate_Base_Type (V_Type) /= Ultimate_Base_Type (TE))
        or else not Is_Unconstrained_Array (TE)
      then
         return TE;
      elsif not Is_Constrained (V_Type) and then Is_Constrained (TE) then
         return TE;
      else
         return V_Type;
      end if;
   end Type_For_Get_Bound;

   ---------------------
   -- Get_Array_Bound --
   ---------------------

   function Get_Array_Bound
     (TE       : Entity_Id;
      Dim      : Nat;
      Is_Low   : Boolean;
      V        : GL_Value;
      For_Type : Boolean := False) return GL_Value
   is
      Typ        : constant Entity_Id    := Type_For_Get_Bound (TE, V);
      Info_Idx   : constant Nat          := Get_Array_Info (Typ);
      Dim_Info   : constant Index_Bounds := Array_Info.Table (Info_Idx + Dim);
      Bound_Info : constant One_Bound    :=
        (if Is_Low then Dim_Info.Low else Dim_Info.High);
      Bound_Idx  : constant Nat := Dim  * 2 + (if Is_Low then 0 else 1);
      --  In the array fat pointer bounds structure, bounds are stored as a
      --  sequence of (lower bound, upper bound) pairs.
      Expr       : constant Node_Id      := Bound_Info.Value;
      Discrim    : constant Entity_Id    := Contains_Discriminant (Expr);
      Result     : GL_Value;

   begin
      Push_Debug_Freeze_Pos;

      --  There are three cases: a constant size, in which case we return
      --  that size, a value, in which case we compute that value, which
      --  may involve a discriminant, and an unconstrained array, in which
      --  case we have a fat pointer and extract the bounds from it.

      if Bound_Info.Cnst /= No_Uint then
         Result := Const_Int (Dim_Info.Bound_Type, Bound_Info.Cnst);
      elsif Present (Expr) then

         --  If we're looking for the size of a type (meaning the max size)
         --  and this expression involves a discriminant, use the minimum
         --  or maxium value of the bound subtype or the discriminant's
         --  subtype.  Otherwise, just evaluate the expression.

         if For_Type and then Present (Discrim) then
            declare
               Bound_Type  : constant Entity_Id := Dim_Info.Bound_Subtype;
               Discr_Type  : constant Entity_Id := Full_Etype (Discrim);
               Bound_Limit : constant Node_Id   :=
                 (if Is_Low then Type_Low_Bound (Bound_Type)
                  else Type_High_Bound (Bound_Type));
               Discr_Limit : constant Node_Id   :=
                 (if Is_Low then Type_Low_Bound (Discr_Type)
                  else Type_High_Bound (Discr_Type));
               Bound_Val   : constant GL_Value  :=
                 Convert_To_Elementary_Type (Emit_Safe_Expr (Bound_Limit),
                                             Dim_Info.Bound_Type);
               Discr_Val   : constant GL_Value  :=
                 Convert_To_Elementary_Type (Emit_Safe_Expr (Discr_Limit),
                                             Dim_Info.Bound_Type);
            begin
               Result := (if Is_Low then Build_Max (Bound_Val, Discr_Val)
                          else Build_Min (Bound_Val, Discr_Val));
            end;
         else
            Result := Build_Type_Conversion (Expr, Dim_Info.Bound_Type);
         end if;
      else
         --  We now should have the unconstrained case.  Make sure we do.
         pragma Assert (Is_Unconstrained_Array (TE)
                          and then Relationship (V) /= Reference);

         Result := Extract_Value
           (Dim_Info.Bound_Type, Get (V, Bounds), (1 => Bound_Idx),
            (if Is_Low then "low-bound" else "high-bound"));

      end if;

      Pop_Debug_Freeze_Pos;
      return Result;
   end Get_Array_Bound;

   ---------------------------------
   --  Use_Discriminant_For_Bound --
   ---------------------------------

   function Use_Discriminant_For_Bound (E : Entity_Id) return GL_Value is
      Rec_Type : constant Entity_Id := Full_Scope (E);
      Match    : constant GL_Value  := Get_Matching_Value (Rec_Type);

   begin
      return Get (Record_Field_Offset (Match, E), Data);

   end Use_Discriminant_For_Bound;

   ----------------------
   -- Get_Array_Length --
   ----------------------

   function Get_Array_Length
     (TE       : Entity_Id;
      Dim      : Nat;
      V        : GL_Value;
      For_Type : Boolean := False) return GL_Value
   is
      Low_Bound  : constant GL_Value :=
        Get_Array_Bound (TE, Dim, True, V, For_Type);
      High_Bound : constant GL_Value :=
        Get_Array_Bound (TE, Dim, False, V, For_Type);

   begin
      --  The length of an array that has the maximum range of its type is
      --  not representable in that type (it's one too high).  Rather than
      --  trying to find some suitable type, we use Size_Type, which will
      --  also make thing simpler for some of our callers.

      return Bounds_To_Length (Low_Bound, High_Bound, Size_Type);
   end Get_Array_Length;

   -------------------------------
   -- Get_Array_Size_Complexity --
   -------------------------------

   function Get_Array_Size_Complexity
     (TE : Entity_Id; For_Type : Boolean := False) return Nat
   is
      Info_Idx    : constant Nat := Get_Array_Info (TE);

   begin
      return Complexity : Nat :=
        Get_Type_Size_Complexity (Full_Component_Type (TE), True)
      do
         for Dim in 0 .. Number_Dimensions (TE) - 1 loop
            declare
               Dim_Info : constant Index_Bounds
                 := Array_Info.Table (Info_Idx + Dim);
            begin
               Complexity := (Complexity +
                                Bound_Complexity (Dim_Info.Low, For_Type) +
                                Bound_Complexity (Dim_Info.High, For_Type));
            end;
         end loop;
      end return;
   end Get_Array_Size_Complexity;

   --------------------------------
   -- Create_String_Literal_Type --
   --------------------------------

   function Create_String_Literal_Type
     (TE : Entity_Id; Comp_Typ : Type_T) return Type_T
   is
      First      : constant Uint         :=
        Get_Uint_Value (String_Literal_Low_Bound (TE));
      Length     : constant Uint         := String_Literal_Length (TE);
      Last       : constant Uint         := First + Length - 1;
      Low_Bound  : constant One_Bound    :=
        (Cnst => First, Value => Empty, Dynamic => False);
      High_Bound : constant One_Bound    :=
        (Cnst => Last, Value => Empty, Dynamic => False);
      Dim_Info   : constant Index_Bounds
        := (Bound_Type    => Standard_Integer,
            Bound_Subtype => Standard_Integer,
            Low           => Low_Bound,
            High          => High_Bound);
      Result_Typ : constant Type_T       :=
        Array_Type (Comp_Typ, unsigned (UI_To_Int (Length)));

   begin
      --  It's redundant to set the type here, since our caller will set it,
      --  but we have to set it in order to set the array info.

      Set_Type (TE, Result_Typ);
      Array_Info.Append (Dim_Info);
      Set_Array_Info (TE, Array_Info.Last);
      return Result_Typ;

   end Create_String_Literal_Type;

   -----------------------
   -- Create_Array_Type --
   -----------------------

   function Create_Array_Type (TE : Entity_Id) return Type_T is
      Unconstrained     : constant Boolean   := not Is_Constrained (TE);
      Comp_Type         : constant Entity_Id := Full_Component_Type (TE);
      Base_Type         : constant Entity_Id := Implementation_Base_Type (TE);
      Must_Use_Fake     : Boolean            := Is_Dynamic_Size (Comp_Type);
      This_Dynamic_Size : Boolean            := Must_Use_Fake or Unconstrained;
      CT_To_Use         : constant Entity_Id :=
        (if Must_Use_Fake then Standard_Short_Short_Integer else Comp_Type);
      Typ               : Type_T             := Create_Type (CT_To_Use);
      --  This must be before the next line because it may recurse
      First_Info        : constant Nat       := Array_Info.Last + 1;
      Dim               : Nat                := 0;
      Index             : Entity_Id;
      Base_Index        : Entity_Id;

   begin
      if Ekind (TE) = E_String_Literal_Subtype then
         return Create_String_Literal_Type (TE, Typ);
      end if;

      --  We loop through each dimension of the array creating the entries
      --  for Array_Info.  If the component type is of variable size or if
      --  either bound of an index is a dynamic size, this type is of
      --  dynamic size.  We could use an opaque type in that case, but
      --  we have numerous array subtypes that should be treated identically
      --  but couldn't if we took that approach.  However, all of those
      --  subtypes will have the same component type.  If that component
      --  type is of fixed size, we can make an LLVM array [0 x CT] where
      --  CT is the component type.  Otherwise, we have to use [0 x i8].
      --  We refer to both of these cases as creating a "fake" type.

      Index      := First_Index (TE);
      Base_Index := First_Index (Base_Type);
      while Present (Index) loop
         declare
            Idx_Range : constant Node_Id        := Get_Dim_Range (Index);
            --  Sometimes, the frontend leaves an identifier that
            --  references an integer subtype instead of a range.

            Index_Type : constant Entity_Id     := Full_Etype (Index);
            Index_Base : constant Entity_Id     :=
              Implementation_Base_Type (Index_Type);

            LB          : constant Node_Id      := Low_Bound (Idx_Range);
            HB          : constant Node_Id      := High_Bound (Idx_Range);
            Dim_Info    : constant Index_Bounds :=
              (Bound_Type    => Index_Base,
               Bound_Subtype => Full_Etype (Base_Index),
               Low           => Build_One_Bound (LB, Unconstrained),
               High          => Build_One_Bound (HB, Unconstrained));
            --  We have to be careful here and flag the type of the index
            --  from that of the base type since we can have index ranges
            --  that are outside the base type if the subtype is superflat
            --  (see C37172C).  We also need to record the subtype of the
            --  index as it appears in the base array type since that's
            --  what's used to compute the min/max sizes of objects.

         begin
            --  Update whether or not this will be of dynamic size and
            --  whether we must use a fake type based on this dimension.
            --  Then record it.  Note that LLVM only allows the range of an
            --  array to be in the range of "unsigned".  So we have to treat
            --  a too-large constant as if it's of variable size.

            if Dim_Info.Low.Dynamic or else Dim_Info.High.Dynamic then
               This_Dynamic_Size := True;
               if Dim /= 0 then
                  Must_Use_Fake := True;
               end if;
            end if;

            Array_Info.Append (Dim_Info);
            Next_Index (Index);
            Next_Index (Base_Index);
            Dim := Dim + 1;
         end;
      end loop;

      --  If we must use a fake type, make one.  Otherwise loop through
      --  the types making the LLVM type.

      if Must_Use_Fake then
         Typ := Array_Type (Typ, 0);
      else
         for I in reverse First_Info .. Array_Info.Last loop
            declare
               Dim_Info : constant Index_Bounds := Array_Info.Table (I);
               Low      : constant One_Bound    := Dim_Info.Low;
               High     : constant One_Bound    := Dim_Info.High;
               Dynamic  : constant Boolean      := Low.Dynamic or High.Dynamic;
               Rng      : unsigned              := 0;
            begin
               if not Dynamic and then Low.Cnst <= High.Cnst
                 and then High.Cnst - Low.Cnst < Int'Last - 1
               then
                  Rng := unsigned (UI_To_Int (High.Cnst - Low.Cnst) + 1);
               end if;

               Typ := Array_Type (Typ, Rng);
            end;
         end loop;
      end if;

      --  It's redundant to set the type here, since our caller will set it,
      --  but we have to set it in order to set the array info.

      Set_Type (TE, Typ);
      Set_Is_Dynamic_Size (TE, This_Dynamic_Size);
      Set_Array_Info (TE, First_Info);

      return Typ;
   end Create_Array_Type;

   ------------------------------
   -- Create_Array_Bounds_Type --
   ------------------------------

   function Create_Array_Bounds_Type (TE : Entity_Id) return Type_T
   is
      Dims       : constant Nat := Number_Dimensions (TE);
      Fields     : aliased Type_Array (Nat range 0 .. 2 * Dims - 1);
      First_Info : constant Nat := Get_Array_Info (TE);
      J          : Nat          := 0;

   begin
      for I in Nat range 0 .. Dims - 1 loop
         Fields (J) :=
           Create_Type (Array_Info.Table (First_Info + I).Bound_Type);
         Fields (J + 1) := Fields (J);
         J := J + 2;
      end loop;

      return Build_Struct_Type (Fields);
   end Create_Array_Bounds_Type;

   --------------------
   -- Get_Bound_Size --
   --------------------

   function Get_Bound_Size (TE : Entity_Id) return GL_Value is
      T : constant Type_T := Create_Array_Bounds_Type (TE);
   begin
      return Align_To (Get_LLVM_Type_Size (T),
                       Size_Const_Int (ULL (Get_Type_Alignment (T))),
                       Size_Const_Int (ULL (Get_Type_Alignment (TE))));
   end Get_Bound_Size;

   ------------------------
   -- Maybe_Store_Bounds --
   ------------------------

   procedure Maybe_Store_Bounds
     (Dest, Src : GL_Value; Src_Type : Entity_Id; For_Unconstrained : Boolean)
   is
      Dest_Type : constant Entity_Id := Related_Type (Dest);

   begin
      --  Only do anything if the destination has a nominal constrained
      --  subtype or (if we're asked) if it has an unconstrained type.

      if Is_Array_Type (Dest_Type)
        and then (Is_Constr_Subt_For_UN_Aliased (Dest_Type)
                    or else (For_Unconstrained
                               and then not Is_Constrained (Dest_Type)))
      then
         Store (Get_Array_Bounds (Src_Type, Src_Type, Src),
                Get (Dest, Reference_To_Bounds));
      end if;
   end Maybe_Store_Bounds;

   -----------------------------------
   -- Create_Array_Fat_Pointer_Type --
   -----------------------------------

   function Create_Array_Fat_Pointer_Type (TE : Entity_Id) return Type_T is
   begin
      return Build_Struct_Type
        ((1 => Pointer_Type (Create_Type (TE), 0),
          2 => Pointer_Type (Create_Array_Bounds_Type (TE), 0)));
   end Create_Array_Fat_Pointer_Type;

   ---------------------------
   -- Contains_Discriminant --
   ---------------------------

   function Contains_Discriminant (N : Node_Id) return Entity_Id is
      Found_Discriminant : Entity_Id := Empty;

      function See_If_Discriminant (N : Node_Id) return Traverse_Result;
      --  Scan a single node looking for a discriminant, setting above if so

      procedure Scan is new Traverse_Proc (See_If_Discriminant);
      --  Used to scan an expression looking for a discriminant

      -------------------------
      -- See_If_Discriminant --
      -------------------------

      function See_If_Discriminant (N : Node_Id) return Traverse_Result is
      begin
         if Nkind (N) = N_Identifier and then Present (Entity (N))
           and then Ekind (Entity (N)) = E_Discriminant
         then
            Found_Discriminant := Entity (N);
            return Abandon;
         else
            return OK;
         end if;
      end See_If_Discriminant;

   begin
      Scan (N);
      return Found_Discriminant;
   end Contains_Discriminant;

   ------------------------
   -- Get_Array_Elements --
   ------------------------

   function Get_Array_Elements
     (V        : GL_Value;
      TE       : Entity_Id;
      For_Type : Boolean := False) return GL_Value is
   begin
      return Size : GL_Value := Size_Const_Int (Uint_1) do

        --  Go through every array dimension.  Get its size and
        --  multiply all of them together.

         for Dim in Nat range 0 .. Number_Dimensions (TE) - 1 loop
            Size := NSW_Mul (Size, Get_Array_Length (TE, Dim, V, For_Type));
         end loop;
      end return;
   end Get_Array_Elements;

   -------------------------
   -- Get_Array_Type_Size --
   -------------------------

   function Get_Array_Type_Size
     (TE       : Entity_Id;
      V        : GL_Value;
      For_Type : Boolean := False) return GL_Value
   is
      Comp_Type     : constant Entity_Id := Full_Component_Type (TE);
      Comp_Size     : constant GL_Value  :=
        Get_Type_Size (Comp_Type, For_Type => True);
      Num_Elements  : constant GL_Value  :=
        Get_Array_Elements (V, TE, For_Type);

   begin
      return NSW_Mul
        (Convert_To_Size_Type (Comp_Size), Convert_To_Size_Type (Num_Elements),
         "size");
   end Get_Array_Type_Size;

   ---------------------------
   -- Emit_Others_Aggregate --
   ---------------------------

   procedure Emit_Others_Aggregate (LValue : GL_Value; N : Node_Id) is
      TE    : constant Entity_Id := Full_Etype (N);
      Align : constant unsigned  := Get_Type_Alignment (TE);
      E     : Node_Id            :=
        Expression (First (Component_Associations (N)));
      Value : GL_Value;

   begin
      --  Find the innermost N_Aggregate and get the value to use

      while Nkind (E) = N_Aggregate and then Is_Others_Aggregate (E) loop
         E := Expression (First (Component_Associations (E)));
      end loop;

      --  If the type is floating-point, the front-end has verified that
      --  it's zero, so use that.  Otherwise, evaluate the value and
      --  convert it to 8 bits.

      if Is_Floating_Point_Type (Full_Etype (E)) then
         Value := Const_Null (Standard_Short_Short_Integer);
      else
         Value := Build_Type_Conversion (E, Standard_Short_Short_Integer);
      end if;

      Call (Build_Intrinsic (Memset, "llvm.memset.p0i8.i", Size_Type),
            (1 => Pointer_Cast (Get (LValue, Reference), Standard_A_Char),
             2 => Value,
             3 => Get_Type_Size (TE),
             4 => Const_Int_32 (Align),
             5 => Const_False));  --  Is_Volatile
   end Emit_Others_Aggregate;

   --------------------------
   -- Emit_Array_Aggregate --
   --------------------------

   function Emit_Array_Aggregate
     (N              : Node_Id;
      Dims_Left      : Pos;
      Indices_So_Far : Index_Array;
      Value_So_Far   : GL_Value) return GL_Value
   is
      Comp_Type : constant Entity_Id := Full_Component_Type (Full_Etype (N));
      Cur_Index : Nat                := 0;
      Expr      : Node_Id;

   begin
      --  The back-end supports exactly two types of array aggregates.
      --  One, which we handle here, is for a fixed-size aggregate of
      --  fixed-size components.  The other are very special cases of
      --  Others that are tested for in Aggr_Assignment_OK_For_Backend
      --  in Exp_Aggr.  We handle them in Emit_Assignment.

      Expr := First (Expressions (N));
      return Cur_Value : GL_Value := Value_So_Far do
         while Present (Expr) loop

            --  If this is a nested N_Aggregate and we have dimensions left
            --  in the outer array, use recursion to fill in the aggregate.

            if Nkind_In (Expr, N_Aggregate, N_Extension_Aggregate)
              and then Dims_Left > 1
            then
               Cur_Value := Emit_Array_Aggregate
                 (Expr, Dims_Left - 1, Indices_So_Far & (1 => Cur_Index),
                  Cur_Value);

            else
               Cur_Value := Insert_Value
                 (Cur_Value, Build_Type_Conversion (Expr, Comp_Type),
                  Indices_So_Far & (1 => Cur_Index));
            end if;

            Cur_Index := Cur_Index + 1;
            Next (Expr);
         end loop;
      end return;
   end Emit_Array_Aggregate;

   ----------------------
   -- Get_Array_Bounds --
   ----------------------

   function Get_Array_Bounds
     (TE, V_Type : Entity_Id; V : GL_Value) return GL_Value
   is
      Info_Idx   : constant Nat := Get_Array_Info (TE);

   begin
      return Bound_Val : GL_Value := Get_Undef_Relationship (TE, Bounds) do
         for Dim in Nat range 0 .. Number_Dimensions (TE) - 1 loop
            declare
               --  The type of the bound of the array we're using for the
               --  bounds may not be the same as the type of the bound in
               --  the unconstrained array, so be sure to convert
               --  (C46042A).

               Bound_Type           : constant Entity_Id :=
                 Array_Info.Table (Info_Idx + Dim).Bound_Type;
               Low_Bound            : constant GL_Value  :=
                 Get_Array_Bound (V_Type, Dim, True, V);
               High_Bound           : constant GL_Value  :=
                 Get_Array_Bound (V_Type, Dim, False, V);
               Converted_Low_Bound  : constant GL_Value  :=
                 Convert_To_Elementary_Type (Low_Bound, Bound_Type);
               Converted_High_Bound : constant GL_Value  :=
                 Convert_To_Elementary_Type (High_Bound, Bound_Type);

            begin
               Bound_Val := Insert_Value
                 (Bound_Val, Converted_Low_Bound, (1 => Dim * 2));

               Bound_Val := Insert_Value
                 (Bound_Val, Converted_High_Bound, (1 => Dim * 2 + 1));
            end;
         end loop;
      end return;
   end Get_Array_Bounds;

   -----------------------
   -- Get_GEP_Safe_Type --
   -----------------------

   function Get_GEP_Safe_Type (V : GL_Value) return Entity_Id is
      Int_Types : constant array (Nat range <>) of Entity_Id :=
        (Standard_Short_Short_Integer, Standard_Short_Integer,
         Standard_Integer, Standard_Long_Integer, Standard_Long_Long_Integer);
      Our_Type  : constant Entity_Id := Full_Etype (V);

   begin
      --  If we are of an unsigned type narrower than Size_Type, we must find
      --  a wider type to use.  We use the first, which will be the narrowest.

      if not Is_Unsigned_Type (Our_Type)
        or else RM_Size (Our_Type) >= RM_Size (Size_Type)
      then
         return Our_Type;
      end if;

      for Typ of Int_Types loop
         if RM_Size (Typ) > RM_Size (Our_Type) then
            return Typ;
         end if;
      end loop;

      return Empty;
   end Get_GEP_Safe_Type;

   ------------------------
   -- Get_Indexed_LValue --
   ------------------------

   function Get_Indexed_LValue
     (Indexes : List_Id; V : GL_Value) return GL_Value
   is
      Array_Type : constant Entity_Id := Full_Designated_Type (V);
      Comp_Type  : constant Entity_Id := Full_Component_Type (Array_Type);
      Array_Data : constant GL_Value  := Get (V, Reference);
      J          : Nat                := 2;
      N          : Node_Id;
      Idxs       : GL_Value_Array (1 .. List_Length (Indexes) + 1) :=
        (1 => Size_Const_Null, others => <>);
      --  Operands for the GetElementPtr instruction: one for the
      --  pointer deference, and then one per array index.

   begin
      N := First (Indexes);
      while Present (N) loop

         --  Adjust the index according to the range lower bound

         declare
            User_Index    : constant GL_Value       := Emit_Safe_Expr (N);
            Dim_Low_Bound : constant GL_Value       :=
              Get_Array_Bound (Array_Type, J - 2, True, V);
            Dim_Op_Type   : constant Entity_Id      :=
              Get_GEP_Safe_Type (Dim_Low_Bound);
            Converted_Index : constant GL_Value     :=
              Convert_To_Elementary_Type (User_Index, Dim_Op_Type);
            Converted_Low_Bound : constant GL_Value :=
              Convert_To_Elementary_Type (Dim_Low_Bound, Dim_Op_Type);

         begin
            Idxs (J) := NSW_Sub
              (Converted_Index, Converted_Low_Bound, "index");
         end;

         J := J + 1;
         N := Next (N);
      end loop;

      --  There are two approaches we can take here.  If we haven't used
      --  a fake type, we can just do a GEP with the values above.

      if not Is_Dynamic_Size (Array_Type) then
         return GEP (Comp_Type, Array_Data, Idxs);
      end if;

      --  Otherwise, we choose a type to use for the indexing.  If the
      --  component type is of fixed size, the array type must be [0 x
      --  CT], and we can count in units of CT.  If CT is of variable
      --  size, we convert the array data type to an i8*, do the
      --  indexing computation in units of bytes, and then convert
      --  back to the array type.  We start with the first index then
      --  for each dimension after the first, multiply by the size of
      --  that dimension and add that index.  Finally, we multiply by
      --  the size of the component type if it isn't the indexing
      --  type.  We do all of this in Size_Type.

      declare
         Use_Comp  : constant Boolean   := not Is_Dynamic_Size (Comp_Type);
         Unit_Type : constant Entity_Id :=
           (if Use_Comp then Comp_Type else Standard_Short_Short_Integer);
         Data      : constant GL_Value  := Ptr_To_Ref (Array_Data, Unit_Type);
         Unit_Mult : constant GL_Value  :=
           (if Use_Comp then Size_Const_Int (Uint_1)
            else Get_Type_Size (Comp_Type, For_Type => True));
         Index     : GL_Value           := Convert_To_Size_Type (Idxs (2));

      begin

         for Dim in 1 .. Number_Dimensions (Array_Type) - 1 loop
            Index := NSW_Add (NSW_Mul (Index,
                                       Get_Array_Length (Array_Type, Dim, V)),
                              Convert_To_Size_Type (Idxs (Dim + 2)));
         end loop;

         Index := NSW_Mul (Index, Unit_Mult);
         return Ptr_To_Ref
           (GEP (Unit_Type, Data, (1 => Index), "arr-lvalue"), Comp_Type);
      end;

   end Get_Indexed_LValue;

   ----------------------
   -- Get_Slice_LValue --
   ----------------------

   function Get_Slice_LValue
     (TE  : Entity_Id;
      Rng : Node_Id;
      V   : GL_Value) return GL_Value
   is
      Array_Data    : constant GL_Value  := Get (V, Reference);
      Arr_Type      : constant Entity_Id := Full_Designated_Type (V);
      Low_Idx_Bound : constant GL_Value  :=
        Get_Array_Bound (Arr_Type, 0, True, V);
      Index_Val     : constant GL_Value  :=
        Emit_Safe_Expr (Low_Bound (Get_Dim_Range (Rng)));
      Dim_Op_Type   : constant Entity_Id :=
        Get_GEP_Safe_Type (Low_Idx_Bound);
      Cvt_Index     : constant GL_Value  :=
        Convert_To_Elementary_Type (Index_Val, Dim_Op_Type);
      Cvt_Low_Bound : constant GL_Value  :=
        Convert_To_Elementary_Type (Low_Idx_Bound, Dim_Op_Type);
      Index_Shift   : constant GL_Value := NSW_Sub (Cvt_Index, Cvt_Low_Bound);
      --  Compute how much we need to offset the array pointer. Slices
      --  can be built only on single-dimension arrays

   begin
      --  Like in Get_Indexed_LValue, we have to hande both the fake and
      --  non-fake cases.  Luckily, we know we're only a single dimension.
      --  However, GEP's result type is a pointer to the component type, so
      --  we need to cast to the result (array) type in both cases.

      if not Is_Dynamic_Size (Arr_Type) then
         return Ptr_To_Ref (GEP (TE, Array_Data,
                                 (Size_Const_Null, Index_Shift),
                                 "arr-lvalue"), TE);
      end if;

      declare
         Comp_Type : constant Entity_Id := Full_Component_Type (Arr_Type);
         Use_Comp  : constant Boolean   := not Is_Dynamic_Size (Comp_Type);
         Unit_Type : constant Entity_Id :=
           (if Use_Comp then Comp_Type else Standard_Short_Short_Integer);
         Data      : constant GL_Value  := Ptr_To_Ref (Array_Data, Unit_Type);
         Unit_Mult : constant GL_Value  :=
           (if Use_Comp then Size_Const_Int (Uint_1)
            else Get_Type_Size (Comp_Type, For_Type => True));
         Index         : constant GL_Value  :=
           NSW_Mul (Convert_To_Size_Type (Index_Shift), Unit_Mult);

      begin
         return Ptr_To_Ref
           (GEP (Arr_Type, Data, (1 => Index), "arr-lvalue"), TE);
      end;

   end Get_Slice_LValue;

   -------------------
   -- Get_Dim_Range --
   -------------------

   function Get_Dim_Range (N : Node_Id) return Node_Id is
   begin
      case Nkind (N) is
         when N_Range
            | N_Signed_Integer_Type_Definition
            | N_Real_Range_Specification =>
            return N;
         when N_Identifier =>
            return Get_Dim_Range (Scalar_Range (Entity (N)));

         when N_Subtype_Indication =>
            declare
               Constr : constant Node_Id := Constraint (N);
            begin
               if Present (Constr) then
                  if Nkind (Constr) = N_Range_Constraint then
                     return Get_Dim_Range (Range_Expression (Constr));
                  end if;
               else
                  return
                    Get_Dim_Range (Scalar_Range (Entity (Subtype_Mark (N))));
               end if;
            end;

         when others =>
            null;
      end case;

      raise Program_Error
        with "Invalid node kind in context: " & Node_Kind'Image (Nkind (N));
      pragma Annotate (Xcov, Exempt_Off);
   end Get_Dim_Range;

end GNATLLVM.Arrays;
