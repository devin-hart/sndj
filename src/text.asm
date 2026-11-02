; text.asm — text rendering into the BG3 shadow tilemap.
; All routines assume A8 X16, DB=$80, D=$0000. The shadow map lives in WRAM;
; NMI DMAs it to VRAM each frame, so nothing here touches the PPU.

.ACCU 8
.INDEX 16

; Fill the whole shadow map with spaces (palette 0, priority).
text_clear:
    lda ui_hires
    beq +
    stz ui_hires            ; back to Mode 1: the NMI restores the classic
    stz ui_xoff             ; palette image
    lda #$01
    sta pal_dirty
+
    rep #$30
.ACCU 16
    lda #ATTR_TEXT          ; tile 0 = space
    ldx #$0000
@loop:
    sta.w SHADOW_BG3,x
    inx
    inx
    cpx #$0800
    bne @loop
    sep #$20
.ACCU 8
    stz.w sd_valid          ; the SONG/LIVE grid must repaint after a clear
    rts

; Compute shadow byte offset from text_x/text_y -> X.
; Relies on text_y living directly after text_x.
text_dest:
    rep #$30
.ACCU 16
    lda text_x              ; lo = x, hi = y
    pha
    and #$FF00
    lsr
    lsr                     ; y*64
    sta tmp1
    pla
    and #$00FF
    asl                     ; x*2
    ora tmp1                ; disjoint bits: x*2 <= 62
    tax
    sep #$20
.ACCU 8
    rts

; Print NUL-terminated string. X = string address (in DB), text_x/y = position,
; text_attr = tilemap attribute bits. Advances text_x by the string length.
text_puts:
    bit ui_hires
    bpl +
    jsl hr_puts
    rts
+
    stx tmp0
    jsr text_dest
    txy
    jsr text_inv            ; tmp1 = glyph-set offset, fixed for the string
    ldx tmp0
@loop:
    lda.w $0000,x
    beq @done
    cmp #'a'
    bcc @upper
    sbc #32                 ; fold lowercase (git hashes) to uppercase
@upper:
    sec
    sbc #32
    rep #$20
.ACCU 16
    and #$00FF
    clc
    adc tmp1                ; +96 inverted set for ACCENT/PLAY, else +0
    ora text_attr
    sta.w SHADOW_BG3,y
    sep #$20
.ACCU 8
    inx
    iny
    iny
    inc text_x
    bra @loop
@done:
    rts

; tmp1 = 96 when text_attr draws as a negative (ACCENT/PLAY use the inverted
; glyph set at +96), else 0. 16-bit store, like text_dest's use of tmp1.
; Clobbers A only; returns A8.
text_inv:
    rep #$20
.ACCU 16
    lda text_attr
    cmp #ATTR_ACCENT
    beq @inv
    cmp #ATTR_PLAY
    beq @inv
    stz tmp1
    sep #$20
.ACCU 8
    rts
@inv:
.ACCU 16
    lda #96
    sta tmp1
    sep #$20
.ACCU 8
    rts

; Print a single glyph. A = raw tile index, position/attr as text_puts.
; Advances text_x.
text_puttile:
    bit ui_hires
    bpl +
    jsl hr_puttile
    rts
+
    pha
    jsr text_dest
    pla
    rep #$20
.ACCU 16
    and #$00FF
    ; accent draws as a negative (inverted glyph set at +96)
    pha
    lda text_attr
    cmp #ATTR_ACCENT
    beq @invert
    cmp #ATTR_PLAY
    beq @invert
    pla
    bra @plain
@invert:
    pla
    clc
    adc #96
@plain:
    ora text_attr
    sta.w SHADOW_BG3,x
    sep #$20
.ACCU 8
    inc text_x
    rts

; Print A as two uppercase hex digits at text_x/y. Advances text_x by 2.
; One text_dest + one attribute test for both digits (this is the hottest
; glyph call: every row label, chain, instrument and value cell). Exit state
; matches the old two-text_puttile version: X = the second digit's offset.
text_hex8:
    bit ui_hires
    bpl +
    jsl hr_hex8
    rts
+
    pha
    jsr text_dest           ; X = first digit's offset
    jsr text_inv            ; tmp1 = 0 / 96
    pla
    pha
    lsr
    lsr
    lsr
    lsr
    jsr @word
    sta.w SHADOW_BG3,x
    sep #$20
.ACCU 8
    pla
    and #$0F
    jsr @word
    sta.w SHADOW_BG3 + 2,x
    sep #$20
.ACCU 8
    inx
    inx
    inc text_x
    inc text_x
    rts
; A8 = nibble -> A16 = finished tilemap word (returns with M clear)
@word:
    cmp #10
    bcc @num
    adc #6                  ; carry set: +7 total ('A'-'0'-10)
@num:
    adc #'0'
    sec
    sbc #32                 ; to tile index
    rep #$20
.ACCU 16
    and #$00FF
    clc
    adc tmp1
    ora text_attr
    rts
.ACCU 8

; long-callable entries for the bank-7 hi-res screen code
song_head_glyph_l:
    jsr song_head_glyph
    rtl
song_cell_attr_l:
    jsr song_cell_attr
    rtl
text_puts_l:
    jsr text_puts
    rtl
text_puttile_l:
    jsr text_puttile
    rtl
text_hex8_l:
    jsr text_hex8
    rtl
text_clear_l:
    jsr text_clear
    rtl
draw_note_l:
    jsr draw_note
    rtl
cell_attr_l:
    jsr cell_attr
    rtl
phrase_update_l:
    jsr phrase_update
    rtl
phrase_init_l:
    jsr phrase_init
    rtl
engine_toggle_l:
    jsr engine_toggle
    rtl
row_is_kit_l:
    jsr row_is_kit
    rtl
draw_kit_name_l:
    jsr draw_kit_name
    rtl
draw_slice_name_l:
    jsr draw_slice_name
    rtl
