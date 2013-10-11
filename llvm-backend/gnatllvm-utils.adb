with Namet; use Namet;
with Nlists;   use Nlists;

package body GNATLLVM.Utils is

   function Index_In_List (N : Node_Id) return Natural is
      L : constant List_Id := List_Containing (N);
      Cur_N : Node_Id := First (L);
      I : Natural := 1;
   begin

      while Present (Cur_N) loop
         exit when Cur_N = N;
         I := I + 1;
         Cur_N := Next (Cur_N);
      end loop;

      return I;
   end Index_In_List;

   ------------------------
   -- Is_Binary_Operator --
   ------------------------

   function Is_Binary_Operator (Node : Node_Id) return Boolean is
     (case Nkind (Node) is
         when N_Op_Add | N_Op_Eq | N_Op_Subtract |
              N_Op_Divide | N_Op_Multiply | N_Op_Gt | N_Op_Lt |
              N_Op_Le | N_Op_Ge | N_Op_Ne => True,
         when others => False);

   -------------
   -- Discard --
   -------------

   procedure Discard (V : Value_T) is
      pragma Unreferenced (V);
   begin
      null;
   end Discard;

   --------------
   -- Get_Name --
   --------------

   function Get_Name (E : Entity_Id) return String is
   begin
      return Get_Name_String (Chars (E));
   end Get_Name;

   -------------
   -- Iterate --
   -------------

   function Iterate (L : List_Id) return List_Iterator
   is
      Len : constant Nat := List_Length (L);
      A : List_Iterator (1 .. Len);
      N : Node_Id := First (L);
      I : Nat := 1;
   begin
      while Present (N) loop
         A (I) := N;
         I := I + 1;
         N := Next (N);
      end loop;
      return A;
   end Iterate;

   ---------------------
   -- Dump_LLVM_Value --
   ---------------------

   procedure Dump_LLVM_Value (V : Value_T) is
   begin
      Dump_Value (V);
   end Dump_LLVM_Value;

   ----------------------
   -- Dump_LLVM_Module --
   ----------------------

   procedure Dump_LLVM_Module (M : Module_T) is
   begin
      Dump_Module (M);
   end Dump_LLVM_Module;

end GNATLLVM.Utils;
