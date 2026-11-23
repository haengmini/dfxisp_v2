`timescale 1ns/1ps
module rm_reference_tb;
    reg ap_clk = 0, ap_rst_n = 0;
    always #5 ap_clk = ~ap_clk;
    wire ap_start, ap_done, ap_idle, ap_ready, rm_ap_idle;

    reg [6:0] s_axi_awaddr = 0, s_axi_araddr = 0;
    reg [31:0] s_axi_wdata = 0;
    reg [3:0] s_axi_wstrb = 0;
    reg s_axi_awvalid = 0, s_axi_wvalid = 0, s_axi_bready = 0;
    reg s_axi_arvalid = 0, s_axi_rready = 0;
    wire s_axi_awready, s_axi_wready, s_axi_bvalid, s_axi_arready, s_axi_rvalid;
    wire [1:0] s_axi_bresp, s_axi_rresp;
    wire [31:0] s_axi_rdata;
    wire [6:0] m_axi_awaddr, m_axi_araddr;
    wire [31:0] m_axi_wdata, m_axi_rdata;
    wire [3:0] m_axi_wstrb;
    wire [1:0] m_axi_bresp, m_axi_rresp;
    wire m_axi_awvalid, m_axi_awready, m_axi_wvalid, m_axi_wready;
    wire m_axi_bvalid, m_axi_bready, m_axi_arvalid, m_axi_arready, m_axi_rvalid, m_axi_rready;
    rm_control controller (.*);

    localparam [31:0] RAW = 32'h70000000, RGB = 32'h70300000;
    localparam integer OUT_SIDE = `OUT_SIDE;
    reg [15:0] raw_pixels [0:63];
    reg [31:0] rgb_pixels [0:OUT_SIDE*OUT_SIDE-1];
    reg [31:0] expected [0:OUT_SIDE*OUT_SIDE-1];

    wire m_axi_gmem0_ARVALID, m_axi_gmem0_RREADY;
    wire [63:0] m_axi_gmem0_ARADDR;
    wire [7:0] m_axi_gmem0_ARLEN;
    wire [2:0] m_axi_gmem0_ARSIZE;
    wire [1:0] m_axi_gmem0_ARBURST;
    wire m_axi_gmem0_ARID;
    integer read_left = 0, read_byte = 0, read_step = 0;
    reg m_axi_gmem0_RID = 0;
    wire m_axi_gmem0_ARREADY = read_left == 0;
    wire m_axi_gmem0_RVALID = read_left != 0;
    wire m_axi_gmem0_RLAST = read_left == 1;
    wire [31:0] m_axi_gmem0_RDATA =
        {raw_pixels[(read_byte/4)*2+1], raw_pixels[(read_byte/4)*2]};
    always @(posedge ap_clk) begin
        if (!ap_rst_n) read_left <= 0;
        else if (m_axi_gmem0_ARREADY && m_axi_gmem0_ARVALID) begin
            if (m_axi_gmem0_ARADDR < RAW || m_axi_gmem0_ARADDR >= RAW+128 ||
                m_axi_gmem0_ARSIZE > 2 || m_axi_gmem0_ARBURST != 1)
                $fatal(1, "unexpected RAW address, size or burst: %h", m_axi_gmem0_ARADDR);
            read_byte <= m_axi_gmem0_ARADDR - RAW;
            read_left <= 1 + int'(m_axi_gmem0_ARLEN);
            read_step <= 1 << m_axi_gmem0_ARSIZE;
            m_axi_gmem0_RID <= m_axi_gmem0_ARID;
        end else if (m_axi_gmem0_RVALID && m_axi_gmem0_RREADY) begin
            if (read_byte >= 128) $fatal(1, "RAW burst out of range");
            read_left <= read_left - 1;
            read_byte <= read_byte + read_step;
        end
    end

    wire m_axi_gmem1_AWVALID, m_axi_gmem1_WVALID, m_axi_gmem1_WLAST, m_axi_gmem1_BREADY;
    wire [63:0] m_axi_gmem1_AWADDR;
    wire [7:0] m_axi_gmem1_AWLEN;
    wire [2:0] m_axi_gmem1_AWSIZE;
    wire [1:0] m_axi_gmem1_AWBURST;
    wire [31:0] m_axi_gmem1_WDATA;
    wire [3:0] m_axi_gmem1_WSTRB;
    wire m_axi_gmem1_AWID;
    reg m_axi_gmem1_BID = 0, m_axi_gmem1_BVALID = 0;
    integer write_left = 0, write_word = 0;
    wire m_axi_gmem1_AWREADY = write_left == 0 && !m_axi_gmem1_BVALID;
    wire m_axi_gmem1_WREADY = write_left != 0;
    always @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            m_axi_gmem1_BVALID <= 0;
            write_left <= 0;
        end else begin
            if (m_axi_gmem1_BVALID && m_axi_gmem1_BREADY) m_axi_gmem1_BVALID <= 0;
            if (m_axi_gmem1_AWREADY && m_axi_gmem1_AWVALID) begin
                if (m_axi_gmem1_AWADDR < RGB || m_axi_gmem1_AWADDR >= RGB+4*OUT_SIDE*OUT_SIDE ||
                    m_axi_gmem1_AWSIZE != 2 || m_axi_gmem1_AWBURST != 1)
                    $fatal(1, "unexpected RGB address, size or burst: %h", m_axi_gmem1_AWADDR);
                write_word <= (m_axi_gmem1_AWADDR - RGB)/4;
                write_left <= 1 + int'(m_axi_gmem1_AWLEN);
                m_axi_gmem1_BID <= m_axi_gmem1_AWID;
            end
            if (m_axi_gmem1_WREADY && m_axi_gmem1_WVALID) begin
                if (write_word >= OUT_SIDE*OUT_SIDE || m_axi_gmem1_WLAST !== (write_left == 1))
                    $fatal(1, "unexpected RGB beat %d", write_word);
                for (int lane=0; lane<4; lane++)
                    if (m_axi_gmem1_WSTRB[lane])
                        rgb_pixels[write_word][8*lane +: 8] <= m_axi_gmem1_WDATA[8*lane +: 8];
                write_word <= write_word + 1;
                write_left <= write_left - 1;
                if (write_left == 1) m_axi_gmem1_BVALID <= 1;
            end
        end
    end

    `include "core_instance.vh"

    task automatic write_reg(input int offset, input reg [31:0] datum,
                             input reg [3:0] mask, input int skew = 0,
                             input reg [1:0] response = 0);
        fork
            begin
                repeat (skew > 0 ? skew : 0) @(posedge ap_clk);
                @(negedge ap_clk);
                s_axi_awaddr = offset[6:0]; s_axi_awvalid = 1;
                do @(posedge ap_clk); while (!s_axi_awready);
                @(negedge ap_clk); s_axi_awvalid = 0;
            end
            begin
                repeat (skew < 0 ? -skew : 0) @(posedge ap_clk);
                @(negedge ap_clk);
                s_axi_wdata = datum; s_axi_wstrb = mask; s_axi_wvalid = 1;
                do @(posedge ap_clk); while (!s_axi_wready);
                @(negedge ap_clk); s_axi_wvalid = 0;
            end
        join
        do @(posedge ap_clk); while (!s_axi_bvalid);
        repeat (2) begin
            if (s_axi_bvalid !== 1 || s_axi_bresp !== response) $fatal(1, "BRESP at %h", offset);
            @(posedge ap_clk);
        end
        @(negedge ap_clk); s_axi_bready = 1;
        @(posedge ap_clk); @(negedge ap_clk); s_axi_bready = 0;
    endtask

    task automatic read_reg(input int offset, output reg [31:0] value,
                            input reg [1:0] response = 0);
        @(negedge ap_clk); s_axi_araddr = offset[6:0]; s_axi_arvalid = 1;
        do @(posedge ap_clk); while (!s_axi_arready);
        @(negedge ap_clk); s_axi_arvalid = 0;
        do @(posedge ap_clk); while (!s_axi_rvalid);
        value = s_axi_rdata;
        repeat (2) begin
            if (s_axi_rvalid !== 1 || s_axi_rdata !== value || s_axi_rresp !== response)
                $fatal(1, "RDATA or RRESP at %h", offset);
            @(posedge ap_clk);
        end
        @(negedge ap_clk); s_axi_rready = 1;
        @(posedge ap_clk); @(negedge ap_clk); s_axi_rready = 0;
    endtask

    integer starts = 0, completions = 0;
    reg active = 0;
    always @(negedge ap_clk) begin
        if (ap_rst_n) begin
            if (rm_ap_idle !== ap_idle) $fatal(1, "idle wiring");
            if (!active && ap_start) begin
                starts = starts + 1;
                active = 1;
                if (rm_ap_idle !== 0) $fatal(1, "idle high on start");
                $display("START %0d t=%0t idle=%b", starts, $time, rm_ap_idle);
            end
            if (active && !ap_done && (rm_ap_idle !== 0 || ap_start !== 1))
                $fatal(1, "start did not hold or idle was high before done");
            if (active && ap_done) begin
                if (!ap_ready) $fatal(1, "ready missing at done");
                completions = completions + 1;
                active = 0;
                $display("DONE %0d t=%0t idle=%b", completions, $time, rm_ap_idle);
            end
        end
    end

    reg [31:0] result, concurrent_read;
    reg held_done, held_ready, saw_active;
    initial begin
        repeat (4) @(negedge ap_clk);
        #1 ap_rst_n = 1;
        @(negedge ap_clk);
        if (rm_ap_idle !== 1) $fatal(1, "idle after reset");
        $display("RESET_RELEASE t=%0t idle=%b", $time, rm_ap_idle);
        write_reg(0, 0, '1);
        read_reg(0, result); if (result !== 4) $fatal(1, "AP_CTRL reset: %h", result);
        write_reg(0, 1, 4'b1110, -2);
        read_reg(0, result); if (result !== 4) $fatal(1, "AP_START byte strobe");
        for (int i=4; i<=12; i+=4) begin
            write_reg(i, '1, '1, 2);
            read_reg(i, result); if (result !== 0) $fatal(1, "reserved register");
        end
        write_reg(1, 0, '1, 0, 2'b10);
        read_reg(1, result, 2'b10);

        fork
            write_reg('h10, RAW, '1, -3);
            read_reg(0, concurrent_read);
        join
        if (concurrent_read !== 4) $fatal(1, "independent read/write channel");
        write_reg('h14, 0, '1);
        write_reg('h1c, RGB, '1, 3);
        write_reg('h20, 0, '1);
        write_reg('h28, 'hffff0008, 4'b0001);
        write_reg('h30, 8, '1);
        read_reg('h28, result); if (result !== 8) $fatal(1, "argument write strobe");

        for (int frame=0; frame<3; frame++) begin
            $readmemh($sformatf("raw_%0d.hex",frame), raw_pixels);
            $readmemh($sformatf("rgb_%0d.hex",frame), expected);
            for (int i=0; i<OUT_SIDE*OUT_SIDE; i++) rgb_pixels[i] = 'x;
            held_done = 0; held_ready = 0; saw_active = 0;
            write_reg(0, 1, '1);
            do begin
                read_reg(0, result);
                held_done |= result[1];
                held_ready |= result[3];
                saw_active |= result[0] && !result[2];
                if (result[31:4] !== 0) $fatal(1, "unsupported AP_CTRL bits");
            end while (!(held_done && result[2] && !result[0]));
            if (!held_ready || !saw_active || rm_ap_idle !== 1) $fatal(1, "missing ready or active");
            $display("IDLE_RETURN %0d t=%0t idle=%b", frame+1, $time, rm_ap_idle);
            for (int i=0; i<OUT_SIDE*OUT_SIDE; i++)
                if (rgb_pixels[i] !== expected[i])
                    $fatal(1, "frame %d pixel %d expected %h got %h", frame, i, expected[i], rgb_pixels[i]);
        end
        read_reg(0, result); if (result !== 4) $fatal(1, "done/ready clear-on-read: %h", result);
        read_reg('h38, result); if (result !== OUT_SIDE) $fatal(1, "width");
        read_reg('h48, result); if (result !== OUT_SIDE) $fatal(1, "height");
        if (starts != 3 || completions != 3) $fatal(1, "unexpected frames: %d %d", starts, completions);
        $display("PASS AP_CTRL AXI-Lite RGB 3/3");
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "test timeout");
    end
endmodule
