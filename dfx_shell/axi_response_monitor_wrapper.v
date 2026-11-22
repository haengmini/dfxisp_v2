`timescale 1ns/1ps
// Passive BD wrapper: two AXI4 MONITOR-mode interfaces (every port is an input) + tested observer.
// Full-interface monitor ports are used so the existing shutdown-manager M_AXI interface connection is
// preserved (pin-level nets would override/break it). Wrapper drives nothing on AXI. Unused fields are ignored.
module axi_response_monitor_wrapper (
 (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
 (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF mon_gmem0:mon_gmem1, ASSOCIATED_RESET rst_n" *)
 input wire clk,
 (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
 (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
 input wire rst_n,
 (* X_INTERFACE_MODE = "monitor" *)
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 AWID" *)
 (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4, DATA_WIDTH 32, ADDR_WIDTH 64, ID_WIDTH 1, HAS_BURST 1, HAS_LOCK 1, HAS_CACHE 1, HAS_PROT 1, HAS_QOS 1, HAS_REGION 1, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1" *)
 input wire mon_gmem0_AWID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 AWADDR" *)
 input wire [63:0] mon_gmem0_AWADDR,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 AWLEN" *)
 input wire [7:0] mon_gmem0_AWLEN,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 AWSIZE" *)
 input wire [2:0] mon_gmem0_AWSIZE,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 AWBURST" *)
 input wire [1:0] mon_gmem0_AWBURST,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 AWLOCK" *)
 input wire mon_gmem0_AWLOCK,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 AWCACHE" *)
 input wire [3:0] mon_gmem0_AWCACHE,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 AWPROT" *)
 input wire [2:0] mon_gmem0_AWPROT,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 AWQOS" *)
 input wire [3:0] mon_gmem0_AWQOS,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 AWREGION" *)
 input wire [3:0] mon_gmem0_AWREGION,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 AWVALID" *)
 input wire mon_gmem0_AWVALID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 AWREADY" *)
 input wire mon_gmem0_AWREADY,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 WDATA" *)
 input wire [31:0] mon_gmem0_WDATA,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 WSTRB" *)
 input wire [3:0] mon_gmem0_WSTRB,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 WLAST" *)
 input wire mon_gmem0_WLAST,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 WVALID" *)
 input wire mon_gmem0_WVALID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 WREADY" *)
 input wire mon_gmem0_WREADY,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 BID" *)
 input wire mon_gmem0_BID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 BRESP" *)
 input wire [1:0] mon_gmem0_BRESP,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 BVALID" *)
 input wire mon_gmem0_BVALID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 BREADY" *)
 input wire mon_gmem0_BREADY,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 ARID" *)
 input wire mon_gmem0_ARID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 ARADDR" *)
 input wire [63:0] mon_gmem0_ARADDR,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 ARLEN" *)
 input wire [7:0] mon_gmem0_ARLEN,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 ARSIZE" *)
 input wire [2:0] mon_gmem0_ARSIZE,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 ARBURST" *)
 input wire [1:0] mon_gmem0_ARBURST,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 ARLOCK" *)
 input wire mon_gmem0_ARLOCK,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 ARCACHE" *)
 input wire [3:0] mon_gmem0_ARCACHE,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 ARPROT" *)
 input wire [2:0] mon_gmem0_ARPROT,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 ARQOS" *)
 input wire [3:0] mon_gmem0_ARQOS,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 ARREGION" *)
 input wire [3:0] mon_gmem0_ARREGION,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 ARVALID" *)
 input wire mon_gmem0_ARVALID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 ARREADY" *)
 input wire mon_gmem0_ARREADY,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 RID" *)
 input wire mon_gmem0_RID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 RDATA" *)
 input wire [31:0] mon_gmem0_RDATA,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 RRESP" *)
 input wire [1:0] mon_gmem0_RRESP,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 RLAST" *)
 input wire mon_gmem0_RLAST,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 RVALID" *)
 input wire mon_gmem0_RVALID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem0 RREADY" *)
 input wire mon_gmem0_RREADY,
 (* X_INTERFACE_MODE = "monitor" *)
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 AWID" *)
 (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4, DATA_WIDTH 32, ADDR_WIDTH 64, ID_WIDTH 1, HAS_BURST 1, HAS_LOCK 1, HAS_CACHE 1, HAS_PROT 1, HAS_QOS 1, HAS_REGION 1, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1" *)
 input wire mon_gmem1_AWID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 AWADDR" *)
 input wire [63:0] mon_gmem1_AWADDR,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 AWLEN" *)
 input wire [7:0] mon_gmem1_AWLEN,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 AWSIZE" *)
 input wire [2:0] mon_gmem1_AWSIZE,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 AWBURST" *)
 input wire [1:0] mon_gmem1_AWBURST,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 AWLOCK" *)
 input wire mon_gmem1_AWLOCK,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 AWCACHE" *)
 input wire [3:0] mon_gmem1_AWCACHE,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 AWPROT" *)
 input wire [2:0] mon_gmem1_AWPROT,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 AWQOS" *)
 input wire [3:0] mon_gmem1_AWQOS,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 AWREGION" *)
 input wire [3:0] mon_gmem1_AWREGION,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 AWVALID" *)
 input wire mon_gmem1_AWVALID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 AWREADY" *)
 input wire mon_gmem1_AWREADY,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 WDATA" *)
 input wire [31:0] mon_gmem1_WDATA,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 WSTRB" *)
 input wire [3:0] mon_gmem1_WSTRB,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 WLAST" *)
 input wire mon_gmem1_WLAST,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 WVALID" *)
 input wire mon_gmem1_WVALID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 WREADY" *)
 input wire mon_gmem1_WREADY,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 BID" *)
 input wire mon_gmem1_BID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 BRESP" *)
 input wire [1:0] mon_gmem1_BRESP,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 BVALID" *)
 input wire mon_gmem1_BVALID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 BREADY" *)
 input wire mon_gmem1_BREADY,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 ARID" *)
 input wire mon_gmem1_ARID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 ARADDR" *)
 input wire [63:0] mon_gmem1_ARADDR,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 ARLEN" *)
 input wire [7:0] mon_gmem1_ARLEN,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 ARSIZE" *)
 input wire [2:0] mon_gmem1_ARSIZE,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 ARBURST" *)
 input wire [1:0] mon_gmem1_ARBURST,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 ARLOCK" *)
 input wire mon_gmem1_ARLOCK,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 ARCACHE" *)
 input wire [3:0] mon_gmem1_ARCACHE,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 ARPROT" *)
 input wire [2:0] mon_gmem1_ARPROT,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 ARQOS" *)
 input wire [3:0] mon_gmem1_ARQOS,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 ARREGION" *)
 input wire [3:0] mon_gmem1_ARREGION,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 ARVALID" *)
 input wire mon_gmem1_ARVALID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 ARREADY" *)
 input wire mon_gmem1_ARREADY,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 RID" *)
 input wire mon_gmem1_RID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 RDATA" *)
 input wire [31:0] mon_gmem1_RDATA,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 RRESP" *)
 input wire [1:0] mon_gmem1_RRESP,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 RLAST" *)
 input wire mon_gmem1_RLAST,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 RVALID" *)
 input wire mon_gmem1_RVALID,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 mon_gmem1 RREADY" *)
 input wire mon_gmem1_RREADY,
 input wire safe_reset_req, safe_reset_confirm, quiescent,
 output wire read_fault, write_fault, fault_now, fault_hold
);
 axi_response_error_observer u_observer(
  .clk(clk), .rst_n(rst_n),
  .rvalid(mon_gmem0_RVALID), .rready(mon_gmem0_RREADY), .rresp(mon_gmem0_RRESP),
  .bvalid(mon_gmem1_BVALID), .bready(mon_gmem1_BREADY), .bresp(mon_gmem1_BRESP),
  .safe_reset_req(safe_reset_req), .safe_reset_confirm(safe_reset_confirm), .quiescent(quiescent),
  .read_fault(read_fault), .write_fault(write_fault), .fault_now(fault_now), .fault_hold(fault_hold));
endmodule
