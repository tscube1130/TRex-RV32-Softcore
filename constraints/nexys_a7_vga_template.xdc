## =============================================================================
## nexys_a7_vga_template.xdc
## Template constraints for the separate VGA game path in top_fpga_with_vga.
##
## IMPORTANT:
## - Keep constraints/nexys_a7.xdc for the existing CPU game path.
## - This file maps only the additional VGA-path ports.
## - Source pinout: Digilent Nexys A7 master XDC.
## =============================================================================

## ---- Additional controls for VGA game ---------------------------------------
## Use remaining push buttons to keep existing controls unchanged.
set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports { vga_duck }]      ; # BTNR
set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports { vga_restart }]   ; # BTND

## ---- VGA signals -------------------------------------------------------------
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports { Hsync }]         ; # VGA_HS
set_property -dict { PACKAGE_PIN B12 IOSTANDARD LVCMOS33 } [get_ports { Vsync }]         ; # VGA_VS

## Red (3 bits)
set_property -dict { PACKAGE_PIN A3 IOSTANDARD LVCMOS33 } [get_ports { vgaRed[0] }]      ; # VGA_R[0]
set_property -dict { PACKAGE_PIN B4 IOSTANDARD LVCMOS33 } [get_ports { vgaRed[1] }]      ; # VGA_R[1]
set_property -dict { PACKAGE_PIN C5 IOSTANDARD LVCMOS33 } [get_ports { vgaRed[2] }]      ; # VGA_R[2]

## Green (3 bits)
set_property -dict { PACKAGE_PIN C6 IOSTANDARD LVCMOS33 } [get_ports { vgaGreen[0] }]    ; # VGA_G[0]
set_property -dict { PACKAGE_PIN A5 IOSTANDARD LVCMOS33 } [get_ports { vgaGreen[1] }]    ; # VGA_G[1]
set_property -dict { PACKAGE_PIN B6 IOSTANDARD LVCMOS33 } [get_ports { vgaGreen[2] }]    ; # VGA_G[2]

## Blue (2 bits)
set_property -dict { PACKAGE_PIN B7 IOSTANDARD LVCMOS33 } [get_ports { vgaBlue[0] }]     ; # VGA_B[0]
set_property -dict { PACKAGE_PIN C7 IOSTANDARD LVCMOS33 } [get_ports { vgaBlue[1] }]     ; # VGA_B[1]

## Optional status LEDs for VGA path
## Map to RGB LED16 channels (free in current project constraints).
set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVCMOS33 } [get_ports { vga_run }]        ; # LED16_R
set_property -dict { PACKAGE_PIN M16 IOSTANDARD LVCMOS33 } [get_ports { vga_dead }]       ; # LED16_G
set_property -dict { PACKAGE_PIN R12 IOSTANDARD LVCMOS33 } [get_ports { vga_collision_led }] ; # LED16_B
