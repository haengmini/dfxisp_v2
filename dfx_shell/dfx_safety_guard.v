`timescale 1ns/1ps
// Static domain, same clock as DFXC/checker. CTRL must be registered MMIO.
// CTRL[0]=enable [1]=permit [2]=commit [3]=cancel [4]=fault
// [5]=recover [6]=recovery_verified. Commit/recover are rising-edge commands.
// Cancellation is ONLY possible before the DFXC rising-edge trigger.
module dfx_safety_guard #(parameter integer TIMEOUT_CYCLES=1024)(
 input wire clk, rst_n,
 input wire [7:0] ctrl,
 input wire [1:0] candidate,
 input wire rm_idle, drain_ctrl, drain_read, drain_write,
 input wire shutdown_req, decouple, event_error,
 input wire status_valid, input wire [31:0] dfx_status,
 output wire [1:0] hw_triggers,
 output wire shutdown_ack,
 output wire [31:0] guard_status
);
 reg enabled, fault, pending, inflight, seen_busy, request_seen;
 reg [1:0] target;
 reg [7:0] old_ctrl;
 reg [1:0] pulse;
 reg [31:0] timer;
 wire busy = shutdown_req | decouple;
 wire status_error = status_valid && (dfx_status[6:3]!=0);
 wire full_ok = status_valid && !dfx_status[7] && !status_error && (dfx_status[2:0]==7);
 wire hazard = event_error | status_error | ctrl[4];
 wire commit = ctrl[2] && !old_ctrl[2];
 wire recover = ctrl[5] && !old_ctrl[5];
 wire safe = rm_idle && drain_ctrl && drain_read && drain_write;
 // Combinational kill covers faults/cancel in the pulse cycle, before capture.
 assign hw_triggers = (enabled && !fault && !hazard && ctrl[0] && ctrl[1] && rm_idle && !ctrl[3]) ? pulse : 2'b00;
 assign shutdown_ack = enabled && !fault && !hazard && ctrl[0] && ctrl[1] && shutdown_req && safe;
 assign guard_status = {24'b0,seen_busy,(target==2),inflight,pending,fault,enabled,(shutdown_ack),(!fault && enabled && !pending && !inflight && !busy && !ctrl[1])};
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   enabled<=0; fault<=0; pending<=0; inflight<=0; seen_busy<=0;
   target<=0; old_ctrl<=0; pulse<=0; timer<=0; request_seen<=0;
  end else begin
   old_ctrl<=ctrl; pulse<=0;
   if (candidate==0) request_seen<=0;
   if (hazard) begin
    fault<=1; enabled<=0; pending<=0; timer<=0;
   end else if (recover && ctrl[6] && !ctrl[0] && !ctrl[1] && candidate==0 && !busy && !pending && !inflight && full_ok) begin
    fault<=0; enabled<=0; seen_busy<=0; timer<=0;
   end else if (!fault) begin
    if (!ctrl[0]) begin enabled<=0; pending<=0; end
    else if (!enabled && !busy && !inflight && candidate==0 && full_ok) enabled<=1;
    if (ctrl[3]) begin
     pending<=0;
     // Already emitted trigger cannot be canceled in DFXC. Latch HOLD.
     if (inflight) begin fault<=1; enabled<=0; end
    end else if (enabled && ctrl[0]) begin
     if (!request_seen && !pending && !inflight && !busy && (candidate==1 || candidate==2)) begin
      pending<=1; target<=candidate; request_seen<=1;
     end
     if (commit && pending && !inflight && !busy && ctrl[1] && rm_idle && full_ok) begin
      pulse<=target; pending<=0; inflight<=1; seen_busy<=0; timer<=0;
     end
    end
    if (inflight) begin
     if (busy || (status_valid && !full_ok)) seen_busy<=1;
     if (seen_busy && !busy && full_ok && (dfx_status[23:8]==((target==2)?1:0))) begin
      inflight<=0; seen_busy<=0; timer<=0;
     end else if (timer>=TIMEOUT_CYCLES-1) begin
      fault<=1; enabled<=0; pending<=0;
      // Remain inflight: unknown DFXC pending cannot be safely recovered here.
     end else timer<=timer+1;
    end
   end
  end
 end
endmodule
