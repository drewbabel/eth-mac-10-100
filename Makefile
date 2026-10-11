#   make MOD=<module>           		compile rtl/ + that tb, run (test FAIL exits nonzero)
#   make wave MOD=<module>        		same, then open the waveform in surfer (opens even on FAIL)
#   make view MOD=<module>         		open testbench waveform in surfer (error if .vcd missing)
#   make clean                  		delete build artifacts (build/, *.vcd)

RTL := $(wildcard rtl/*.sv)
TB  := $(firstword $(wildcard tb/$(MOD)_tb.sv))
SIM := build/sim
WAVE_STATE := tb/$(MOD).ron

run:
	@test -n "$(MOD)" || { echo "usage: make MOD=<module>"; exit 1; }
	@mkdir -p build
	iverilog -g2012 -s $(MOD)_tb -o $(SIM) $(RTL) $(TB)
	vvp $(SIM)

wave:
	@test -n "$(MOD)" || { echo "usage: make wave MOD=<module>"; exit 1; }
	@mkdir -p build
	iverilog -g2012 -s $(MOD)_tb -o $(SIM) $(RTL) $(TB)
	-vvp $(SIM)
	surfer $$(ls *.vcd 2>/dev/null | head -1) $$(test -f $(WAVE_STATE) && echo "-s $(WAVE_STATE)") &

view:
	@test -n "$(MOD)" || { echo "usage: make view MOD=<module>"; exit 1; }
	@test -f "tb/$(MOD).ron" || { echo "Error: tb/$(MOD).ron not found"; exit 1; }
	@test -f "$$(ls tb/*.vcd 2>/dev/null | head -1)" || { echo "Error: no .vcd found in tb/"; exit 1; }
	surfer $$(ls tb/*.vcd 2>/dev/null | head -1) -s tb/$(MOD).ron &

clean:
	rm -rf build *.vcd sim_build results.xml

.DEFAULT_GOAL := run
.PHONY: run wave view clean
