`timescale 1ns/1ps

module rm_control (
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI:M_AXI, ASSOCIATED_RESET ap_rst_n" *)
    input  wire        ap_clk,
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        ap_rst_n,
    output reg         ap_start,
    input  wire        ap_done,
    input  wire        ap_idle,
    input  wire        ap_ready,
    output wire        rm_ap_idle,

    (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, ADDR_WIDTH 7, DATA_WIDTH 32" *)
    input  wire [6:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [6:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, ADDR_WIDTH 7, DATA_WIDTH 32" *)
    output wire [6:0]  m_axi_awaddr,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    output wire [31:0] m_axi_wdata,
    output wire [3:0]  m_axi_wstrb,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,
    output wire [6:0]  m_axi_araddr,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready
);
    localparam [1:0] OKAY = 2'b00, SLVERR = 2'b10;
    localparam [1:0] WR_COLLECT = 0, WR_SEND = 1, WR_REPLY = 2, WR_LOCAL = 3;
    localparam [1:0] RD_ACCEPT = 0, RD_SEND = 1, RD_REPLY = 2, RD_LOCAL = 3;

    reg [1:0] write_state, read_state;
    reg       have_address, have_data;
    reg [6:0] write_offset;
    reg [31:0] write_data;
    reg [3:0] write_strobes;
    reg [1:0] local_bresp, local_rresp;
    reg [6:0] read_offset;
    reg [31:0] local_rdata;
    reg done_seen, ready_seen;

    wire take_aw = s_axi_awvalid && s_axi_awready;
    wire take_w = s_axi_wvalid && s_axi_wready;
    wire take_ar = s_axi_arvalid && s_axi_arready;
    wire send_aw = m_axi_awvalid && m_axi_awready;
    wire send_w = m_axi_wvalid && m_axi_wready;
    wire write_command = write_state == WR_COLLECT && have_address && have_data;
    wire read_ap_ctrl = take_ar && s_axi_araddr == 0;

    assign rm_ap_idle = ap_idle;
    assign s_axi_awready = ap_rst_n && write_state == WR_COLLECT && !have_address;
    assign s_axi_wready = ap_rst_n && write_state == WR_COLLECT && !have_data;
    assign s_axi_bvalid = write_state == WR_LOCAL || (write_state == WR_REPLY && m_axi_bvalid);
    assign s_axi_bresp = write_state == WR_LOCAL ? local_bresp : m_axi_bresp;
    assign s_axi_arready = ap_rst_n && read_state == RD_ACCEPT;
    assign s_axi_rvalid = read_state == RD_LOCAL || (read_state == RD_REPLY && m_axi_rvalid);
    assign s_axi_rdata = read_state == RD_LOCAL ? local_rdata : m_axi_rdata;
    assign s_axi_rresp = read_state == RD_LOCAL ? local_rresp : m_axi_rresp;

    assign m_axi_awaddr = write_offset[6:0];
    assign m_axi_wdata = write_data;
    assign m_axi_wstrb = write_strobes;
    assign m_axi_awvalid = write_state == WR_SEND && have_address;
    assign m_axi_wvalid = write_state == WR_SEND && have_data;
    assign m_axi_bready = write_state == WR_REPLY && s_axi_bready;
    assign m_axi_araddr = read_offset;
    assign m_axi_arvalid = read_state == RD_SEND;
    assign m_axi_rready = read_state == RD_REPLY && s_axi_rready;

    always @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            write_state <= WR_COLLECT;
            have_address <= 0;
            have_data <= 0;
            write_offset <= 0;
            write_data <= 0;
            write_strobes <= 0;
            local_bresp <= OKAY;
        end else case (write_state)
            WR_COLLECT: begin
                if (take_aw) begin
                    write_offset <= s_axi_awaddr;
                    have_address <= 1;
                end
                if (take_w) begin
                    write_data <= s_axi_wdata;
                    write_strobes <= s_axi_wstrb;
                    have_data <= 1;
                end
                if (write_command) begin
                    if (write_offset[1:0] != 0 || write_offset < 7'h10) begin
                        local_bresp <= write_offset[1:0] != 0 ? SLVERR : OKAY;
                        have_address <= 0;
                        have_data <= 0;
                        write_state <= WR_LOCAL;
                    end else write_state <= WR_SEND;
                end
            end
            WR_SEND: begin
                if (send_aw) have_address <= 0;
                if (send_w) have_data <= 0;
                if ((!have_address || send_aw) && (!have_data || send_w))
                    write_state <= WR_REPLY;
            end
            WR_REPLY, WR_LOCAL: if (s_axi_bvalid && s_axi_bready) write_state <= WR_COLLECT;
        endcase
    end

    always @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            read_state <= RD_ACCEPT;
            read_offset <= 0;
            local_rdata <= 0;
            local_rresp <= OKAY;
        end else case (read_state)
            RD_ACCEPT: if (take_ar) begin
                if (s_axi_araddr[1:0] != 0 || s_axi_araddr < 7'h10) begin
                    local_rdata <= read_ap_ctrl ? {28'b0, ready_seen, ap_idle, done_seen, ap_start} : 0;
                    local_rresp <= s_axi_araddr[1:0] != 0 ? SLVERR : OKAY;
                    read_state <= RD_LOCAL;
                end else begin
                    read_offset <= s_axi_araddr;
                    read_state <= RD_SEND;
                end
            end
            RD_SEND: if (m_axi_arready) read_state <= RD_REPLY;
            RD_REPLY, RD_LOCAL: if (s_axi_rvalid && s_axi_rready) read_state <= RD_ACCEPT;
        endcase
    end

    always @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            ap_start <= 0;
            done_seen <= 0;
            ready_seen <= 0;
        end else begin
            if (write_command && write_offset == 0 && write_strobes[0] && write_data[0])
                ap_start <= 1;
            else if (ap_ready)
                ap_start <= 0;
            if (ap_done) done_seen <= 1;
            else if (read_ap_ctrl) done_seen <= 0;
            if (ap_ready) ready_seen <= 1;
            else if (read_ap_ctrl) ready_seen <= 0;
        end
    end
endmodule
