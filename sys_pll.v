module sys_pll (
    input  inclk0,
    output c0,
    output locked
);
    // This connects to the hardware ALTPLL block
    altpll #(
        .bandwidth_type("AUTO"),
        .clk0_divide_by(5),       // Divide 50MHz by 5 = 10MHz
        .clk0_duty_cycle(50),
        .clk0_multiply_by(1),
        .clk0_phase_shift("0"),
        .compensate_clock("CLK0"),
        .inclk0_input_frequency(20000), // Period of 50MHz in ps
        .intended_device_family("MAX 10"),
        .lpm_type("altpll"),
        .operation_mode("NORMAL"),
        .pll_type("AUTO"),
        .width_clock(5)
    ) altpll_component (
        .inclk ({1'b0, inclk0}),
        .clk ({4'b0, c0}), // We only use the first clock output (c0)
        .locked (locked),
        .activeclock (),
        .areset (1'b0),
        .clkbad (),
        .clkena ({6{1'b1}}),
        .clkloss (),
        .clkswitch (1'b0),
        .configupdate (1'b0),
        .enable0 (),
        .enable1 (),
        .extclk (),
        .fbin (1'b1),
        .fbmimicbidir (),
        .fbout (),
        .fref (),
        .icdrclk (),
        .pfdena (1'b1),
        .phasecounterselect ({4{1'b1}}),
        .phasedone (),
        .phasestep (1'b1),
        .phaseupdown (1'b1),
        .pllena (1'b1),
        .scanaclr (1'b0),
        .scanclk (1'b0),
        .scanclkena (1'b1),
        .scandata (1'b0),
        .scandataout (),
        .scandone (),
        .scanread (1'b0),
        .scanwrite (1'b0),
        .sclkout0 (),
        .sclkout1 (),
        .vcooverrange (),
        .vcounderrange ()
    );
endmodule