with Ada.Text_IO; use Ada.Text_IO;

-- naimi_trehel.adb
package body Naimi_Trehel is

   procedure Enqueue (Q : in out Message_Queue; M : Message) is
   begin
      if Q.Count >= Q.Items'Last then
         raise Queue_Overflow with "Message queue exceeded safe bounds.";
      end if;
      Q.Count := Q.Count + 1;
      Q.Items (Q.Count) := M;
   end Enqueue;

   function Dequeue (Q : in out Message_Queue) return Message is
      M : Message;
   begin
      if Q.Count = 0 then
         raise Queue_Underflow with "Attempted to dequeue from empty network.";
      end if;
      M := Q.Items (1);
      for I in 1 .. Q.Count - 1 loop
         Q.Items (I) := Q.Items (I + 1);
      end loop;
      Q.Count := Q.Count - 1;
      return M;
   end Dequeue;

   procedure Initialize (Sys : out Distributed_System; Initial_Token_Holder : Valid_Node_ID := 1) is
   begin
      Sys.Queue.Count := 0;
      for I in 1 .. Sys.Num_Nodes loop
         Sys.Nodes (I).Owner := Initial_Token_Holder;
         Sys.Nodes (I).Next_Node := Null_Node;
         Sys.Nodes (I).Requesting := False;
         
         if I = Initial_Token_Holder then
            Sys.Nodes (I).Token_Present := True;
         else
            Sys.Nodes (I).Token_Present := False;
         end if;
      end loop;
   end Initialize;

   procedure Request_Critical_Section (Sys : in out Distributed_System; Node : Valid_Node_ID) is
   begin
      if Sys.Nodes (Node).Token_Present then
         -- Node already holds token; enter immediately
         Sys.Nodes (Node).Requesting := True;
      else
         -- Add self to CS queue and update dynamic tree
         Sys.Nodes (Node).Requesting := True;
         Enqueue (Sys.Queue, (Kind => Request_Msg, Source => Node, Dest => Sys.Nodes (Node).Owner));
         Sys.Nodes (Node).Owner := Node; -- Become root of own sub-tree
      end if;
   end Request_Critical_Section;

   procedure Release_Critical_Section (Sys : in out Distributed_System; Node : Valid_Node_ID) is
   begin
      if not Sys.Nodes (Node).Token_Present then
         raise Critical_Section_Violation with "Node released CS without token ownership.";
      end if;

      Sys.Nodes (Node).Requesting := False;
      
      -- Deferred token passing: grant token to the next queued process if one exists
      if Sys.Nodes (Node).Next_Node /= Null_Node then
         Enqueue (Sys.Queue, (Kind => Token_Msg, Source => Node, Dest => Sys.Nodes (Node).Next_Node));
         Sys.Nodes (Node).Token_Present := False;
         Sys.Nodes (Node).Next_Node := Null_Node;
      end if;
   end Release_Critical_Section;

   procedure Process_Next_Message (Sys : in out Distributed_System; Success : out Boolean) is
      M : Message;
      Dest_Node : Valid_Node_ID;
      Req_Node  : Valid_Node_ID;
      Owner_Node : Valid_Node_ID;
   begin
      if Sys.Queue.Count = 0 then
         Success := False;
         return;
      end if;
      
      M := Dequeue (Sys.Queue);
      Success := True;
      
      case M.Kind is
         when Request_Msg =>
            Dest_Node := M.Dest;
            Req_Node  := M.Source;

            Put_Line ("DBG: handling Request_Msg; Dest=" & Integer'Image (Integer (Dest_Node)) & ", Req=" & Integer'Image (Integer (Req_Node)));
            Put_Line ("DBG: Dest.Owner(before)=" & Integer'Image (Integer (Sys.Nodes (Dest_Node).Owner)) & ", Dest.Token=" & Boolean'Image (Sys.Nodes (Dest_Node).Token_Present) & ", Dest.Req=" & Boolean'Image (Sys.Nodes (Dest_Node).Requesting) & ", Dest.Next=" & Integer'Image (Integer (Sys.Nodes (Dest_Node).Next_Node)));

            -- Find the current owner representative for Dest_Node
            Owner_Node := Dest_Node;
            while Sys.Nodes (Owner_Node).Owner /= Owner_Node loop
               Owner_Node := Sys.Nodes (Owner_Node).Owner;
            end loop;
            Put_Line ("DBG: representative Owner_Node=" & Integer'Image (Integer (Owner_Node)) & ", Owner.Token=" & Boolean'Image (Sys.Nodes (Owner_Node).Token_Present) & ", Owner.Req=" & Boolean'Image (Sys.Nodes (Owner_Node).Requesting) & ", Owner.Next(before)=" & Integer'Image (Integer (Sys.Nodes (Owner_Node).Next_Node)));

            if Owner_Node = Dest_Node then
               -- Destination considers itself the root/owner: handle locally
               if Sys.Nodes (Dest_Node).Token_Present and then not Sys.Nodes (Dest_Node).Requesting then
                  -- Give up token immediately
                  Sys.Nodes (Dest_Node).Token_Present := False;
                  Enqueue (Sys.Queue, (Kind => Token_Msg, Source => Dest_Node, Dest => Req_Node));
                  Put_Line ("DBG: Enqueued Token_Msg: Src=" & Integer'Image (Integer (Dest_Node)) & ", Dest=" & Integer'Image (Integer (Req_Node)) & ", QueueCount=" & Natural'Image (Sys.Queue.Count));
               else
                  -- Enqueue the requestor if currently using or waiting for the token
                  Sys.Nodes (Dest_Node).Next_Node := Node_ID(Req_Node);
                  Put_Line ("DBG: Set Next_Node on Dest=" & Integer'Image (Integer (Dest_Node)) & " to " & Integer'Image (Integer (Req_Node)));
               end if;

            else
               -- Representative is different: operate on Owner_Node (the real owner)
               if Sys.Nodes (Owner_Node).Token_Present and then not Sys.Nodes (Owner_Node).Requesting then
                  -- Owner can forward token immediately
                  Sys.Nodes (Owner_Node).Token_Present := False;
                  Enqueue (Sys.Queue, (Kind => Token_Msg, Source => Owner_Node, Dest => Req_Node));
                  Put_Line ("DBG: Enqueued Token_Msg from Owner_Node=" & Integer'Image (Integer (Owner_Node)) & ", to Req=" & Integer'Image (Integer (Req_Node)) & ", QueueCount=" & Natural'Image (Sys.Queue.Count));
               elsif Sys.Nodes (Owner_Node).Token_Present and Sys.Nodes (Owner_Node).Requesting then
                  -- Owner is in CS; set its Next_Node so it will pass token later
                  Sys.Nodes (Owner_Node).Next_Node := Node_ID(Req_Node);
                  Put_Line ("DBG: Set Next_Node on Owner_Node=" & Integer'Image (Integer (Owner_Node)) & " to " & Integer'Image (Integer (Req_Node)));
               else
                  -- Owner does not hold token: forward one hop to owner by enqueuing a request
                  Enqueue (Sys.Queue, (Kind => Request_Msg, Source => Req_Node, Dest => Owner_Node));
                  Put_Line ("DBG: Enqueued Request_Msg forward: Src=" & Integer'Image (Integer (Req_Node)) & ", Dest=" & Integer'Image (Integer (Owner_Node)) & ", QueueCount=" & Natural'Image (Sys.Queue.Count));
               end if;

               -- Path compression: make the original destination point to the requester
               Sys.Nodes (Dest_Node).Owner := Req_Node;
               Put_Line ("DBG: Path compression: Dest.Owner set to " & Integer'Image (Integer (Req_Node)));
            end if;
            
         when Token_Msg =>
            Sys.Nodes (M.Dest).Token_Present := True;
      end case;
   end Process_Next_Message;

   procedure Process_All_Messages (Sys : in out Distributed_System) is
      Success : Boolean := True;
   begin
      while Success loop
         Process_Next_Message (Sys, Success);
      end loop;
   end Process_All_Messages;

   function Has_Token (Sys : Distributed_System; Node : Valid_Node_ID) return Boolean is
   begin
      return Sys.Nodes (Node).Token_Present;
   end Has_Token;

   function Is_Requesting (Sys : Distributed_System; Node : Valid_Node_ID) return Boolean is
   begin
      return Sys.Nodes (Node).Requesting;
   end Is_Requesting;

   function Pending_Messages (Sys : Distributed_System) return Natural is
   begin
      return Sys.Queue.Count;
   end Pending_Messages;

end Naimi_Trehel;
