`timescale 1ns/1ps
// Static PL clock; passive snoop only. Never reset with RM reset.
// 00 OKAY / 01 EXOKAY accepted; 10 SLVERR / 11 DECERR fail closed.
module axi_response_error_observer(
 input wire clk, rst_n,
 input wire rvalid, rready, input wire [1:0] rresp,
 input wire bvalid, bready, input wire [1:0] bresp,
 input wire safe_reset_req, safe_reset_confirm, quiescent,
 output reg read_fault, write_fault,
 output wire fault_now, fault_hold
);
 wire read_error = rvalid && rready && rresp[1];
 wire write_error = bvalid && bready && bresp[1];
 wire clear_ok = safe_reset_req && safe_reset_confirm && quiescent && !rvalid && !bvalid;
 assign fault_hold = read_fault | write_fault;
 // Look-ahead is essential: sticky-only leaves a trigger/ACK race at the edge.
 assign fault_now = fault_hold | read_error | write_error;
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin read_fault<=0; write_fault<=0; end
  else begin
   if (read_error) read_fault<=1;
   else if (clear_ok) read_fault<=0;
   if (write_error) write_fault<=1;
   else if (clear_ok) write_fault<=0;
  end
 end
endmodule

// Additional authorization outputs are policy signals, NOT bus drivers.
// They must be enforced by the control owner/firewall before accepting ap_start.
module response_authorization_gate(
 input wire response_fault_now, existing_event_error,
 input wire start_request, recovery_request, recovery_confirm,
 output wire guard_event_error, start_authorized, recovery_authorized
);
 assign guard_event_error = existing_event_error | response_fault_now;
 assign start_authorized = start_request && !guard_event_error;
 assign recovery_authorized = recovery_request && recovery_confirm && !guard_event_error;
endmodule
