module up_counter(input c,t, output reg q,q1,q2,q3,q4);
initial
begin
  q =0; 
  q1=0;
  q2=0;
  q3=0;
  q4=0;
end
reg [23:0] count;
always @(posedge c) 
begin
   count <= count + 1;
   if (count == 1562500) 
	begin
	   count <= 0;
      q<=~q;
   end
end
always @(posedge q) 
begin 
    q1<=q1^t;
end
always @(posedge q1) 
begin 
    q2<=q2^t;
end
always @(posedge q2) 
begin 
    q3<=q3^t;
end
always @(posedge q3) 
begin 
    q4<=q4^t;
end
endmodule