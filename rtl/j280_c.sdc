create_clock -name clk_50m -period 20.000 -waveform {0.000 10.000} [get_ports {clk_50m}]
set_clock_uncertainty -setup -from [get_clocks {clk_50m}] -to [get_clocks {clk_50m}] 0.200
set_clock_uncertainty -hold -from [get_clocks {clk_50m}] -to [get_clocks {clk_50m}] 0.100
set_false_path -from [get_ports {rst_n key_zero_calib key_pos_clear key_motor_toggle enc_a enc_b}]
set_false_path -to [get_ports {led_balance led_calib_ok led_motor_run led_rsvd uart_tx}]
create_generated_clock -name adc_launch -source [get_ports {clk_50m}] -divide_by 10 [get_ports {adc_clk}]
create_generated_clock -name adc_sample -source [get_ports {clk_50m}] -edges {9 19 29} [get_nets {adc/sample_clk}]
# Datasheet typ tOD=25ns; 35ns is a trial budget incl. board flight/skew, NOT a guaranteed datasheet max.
set_input_delay -clock adc_launch -max 35.000 [get_ports {adc_data_in[*]}]
set_input_delay -clock adc_launch -min 0.000 [get_ports {adc_data_in[*]}]
# No data-path false or multicycle exceptions: actual 5MHz capture clock is +80ns.
