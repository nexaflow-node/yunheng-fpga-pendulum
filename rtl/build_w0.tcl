set here [file dirname [file normalize [info script]]]
cd $here
set_device -name GW2A-55C GW2A-LV55PG484C8/I7
foreach name {c_adc c_balance_core c_control c_encoder c_keys c_mul32 c_output c_pwm c_sensor c_swing c_trace_buffer c_trace_export c_trace_monitor c_trace_uart c_uart j280_c_top} {add_file [file join $here "$name.v"]}
foreach name {v5_params.vh feedback_shape.vh j280_c.cst j280_c.sdc} {add_file [file join $here $name]}
set_option -top_module j280_c_top
set_option -output_base_name j280_k290_w0
set_option -verilog_std v2001
set_option -use_sspi_as_gpio 1
run all
