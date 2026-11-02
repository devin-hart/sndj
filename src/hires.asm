; hires.asm — the Mode 5 (512 px, 64-column, colour) text renderer.
; UI REWRITE SPIKE (branch ui-rewrite): only SONG uses it so far.
;
; Two layers each hold every other column (tools/makehrfont.py):
;   BG2 2bpp = even columns, shadow = SHADOW_BG3 (rows 0-27)
;   BG1 4bpp = odd columns,  shadow = SHADOW_HRB
; Both shadows use the classic 64-byte row stride, so a cell is
;   y*64 + (x>>1)*2 (+ HRB_OFS on the odd layer) from SHADOW_BG3.
; Glyph g is tile 2g+1 on the even layer and tile 2g on the odd one; no
; glyph pairs are composed at run time, so a glyph costs what it does in
; Mode 1. The odd layer is 4bpp, whose palette 1 shares CGRAM with the
; 2bpp palette 4, so it stores palettes 1 and 4 swapped.
;
; Lives in bank 7 (bank 0 is full): the classic text_* entry points test
; ui_hires and jsl here; these routines return with rtl. They run with
; DB=$80 (unchanged), so string and WRAM reads work as in bank 0.
; Register contract matches the classic routines: A, X, tmp1 clobbered;
; Y, tmp0, tmp2 preserved.

.DEFINE HRB_OFS (SHADOW_HRB - SHADOW_BG3)
.DEFINE HR_MAPBYTES 1792     ; 28 rows x 64 bytes

.BANK 7 SLOT 0
.SECTION "Hires renderer" FREE

.ACCU 8
.INDEX 16

; --- boot: fonts into VRAM, BG1/BG2 bases (inactive until Mode 5) ----------
; called from init_video under force-blank
hr_boot:
    lda #$80
    sta VMAIN
    ldx #VRAM_HR_BG1_CHR
    stx VMADDL
    lda #$01
    sta DMAP0
    lda #$18
    sta BBAD0
    ldx #hr_font4
    stx A1T0L
    lda #:hr_font4
    sta A1B0
    ldx #(hr_font4_end - hr_font4)
    stx DAS0L
    lda #$01
    sta MDMAEN
    ldx #VRAM_HR_BG2_CHR
    stx VMADDL
    ldx #hr_font2
    stx A1T0L
    lda #:hr_font2
    sta A1B0
    ldx #(hr_font2_end - hr_font2)
    stx DAS0L
    lda #$01
    sta MDMAEN
    lda #(VRAM_HR_BG1_MAP >> 8)
    sta BG1SC
    lda #(VRAM_HR_BG2_MAP >> 8)
    sta BG2SC
    lda #((VRAM_HR_BG2_CHR >> 12) << 4) | (VRAM_HR_BG1_CHR >> 12)
    sta BG12NBA
    ; OPTIONS HI-RES from the SRAM header (anything but 1 = off)
    stz opt_hires
    lda.l $700000
    cmp #'S'
    bne @done
    lda.l $700004
    cmp #'1'
    bne @done
    lda.l $70000D
    cmp #$01
    bne @done
    sta opt_hires
@done:
    rtl

; --- NMI: both shadows -> VRAM, Mode 5 on main + sub screen ------------------
nmi_hr:
    lda #$80
    sta VMAIN
    lda #$01
    sta DMAP0
    lda #$18
    sta BBAD0
    stz A1B0                ; bank $00: the WRAM mirror
    ldx #VRAM_HR_BG2_MAP
    stx VMADDL
    ldx #SHADOW_BG3
    stx A1T0L
    ldx #HR_MAPBYTES
    stx DAS0L
    lda #$01
    sta MDMAEN
    ldx #VRAM_HR_BG1_MAP
    stx VMADDL
    ldx #SHADOW_HRB
    stx A1T0L
    ldx #HR_MAPBYTES
    stx DAS0L
    lda #$01
    sta MDMAEN
    lda #$05
    sta BGMODE
    lda #$03                ; BG1 + BG2: Mode 5 shows the even pixels from
    sta TM                  ; the sub screen, so both screens carry them
    sta TS
    lda #$21                ; the sub screen's backdrop is the fixed colour:
    sta COLDATA             ; match CGRAM 0 (#0C1016) or empty cells stripe
    lda #$42
    sta COLDATA
    lda #$82
    sta COLDATA
    lda hr_paldirty
    beq @done
    stz CGADD
    stz DMAP0               ; 1 byte -> CGDATA (it latches pairs itself)
    lda #$22
    sta BBAD0
    ldx #hr_pal
    stx A1T0L
    lda #:hr_pal
    sta A1B0
    ldx #256
    stx DAS0L
    lda #$01
    sta MDMAEN
    stz hr_paldirty
@done:
    jsl ih_nmi              ; INSTR graphics upload (instrhr.asm, bank 8)
    jsr hr_hdma_nmi         ; Beat-row HDMA tint (G6)
    rtl

; --- screen entry: switch the text layer to hi-res ---------------------------
; after text_clear (which cleared SHADOW_BG3 = the even layer)
hr_enter:
    rep #$30
.ACCU 16
    lda #ATTR_TEXT
    ldx #$0000
@clr:
    sta.w SHADOW_HRB,x
    inx
    inx
    cpx #HR_MAPBYTES
    bne @clr
    ldx #$001E
@tab:
    lda.l hr_tab_rom,x      ; tilemap-word bases per palette -> WRAM
    sta.w hr_tab,x          ; (the glyph code indexes them with Y)
    dex
    dex
    bpl @tab
    sep #$20
.ACCU 8
    stz.w hr_sb_valid       ; status bar: redraw on first frame
    lda #$FE
    sta hr_lastch           ; chain panel: redraw on first frame
    lda #$FF
    sta.w hr_meter_scr      ; level meters: redraw on first frame
    lda #$01
    sta hr_paldirty
    lda #32
    sta ui_xoff
    lda #$80
    sta ui_hires            ; last: the NMI switches modes from here on
    rtl

; --- glyph output --------------------------------------------------------------
; A8 = tile index (char - 32) at text_x/text_y with text_attr; advances
; text_x. ACCENT/PLAY draw from the inverted set (+96), as in Mode 1.
hr_put:
    phy
    rep #$30
.ACCU 16
    and #$00FF
    asl
    pha                     ; 2g
    lda text_attr
    xba
    and #$001C
    tay                     ; Y = palette * 4: hr_tab entry
    lda text_x              ; lo = x, hi = y
    and #$FF00
    lsr
    lsr                     ; y*64
    sta tmp1
    lda text_x
    and #$00FE              ; (x>>1)*2
    ora tmp1
    tax
    lda text_x
    lsr                     ; C = odd column
    pla
    bcs @odd
    clc
    adc.w hr_tab,y          ; even layer: tile 2g+1 = (glyph, blank)
    sta.w SHADOW_BG3,x
    bra @out
@odd:
    clc
    adc.w hr_tab + 2,y      ; odd layer: tile 2g = (blank, glyph)
    sta.w SHADOW_HRB,x
@out:
    sep #$20
.ACCU 8
    inc text_x
    ply
    rts

; A8 = byte as two hex digits at text_x/text_y: one position and one
; palette lookup for both (the SONG grid is mostly these)
hr_x2:
    phy
    rep #$30
.ACCU 16
    and #$00FF
    pha
    lda text_attr
    xba
    and #$001C
    tay
    lda text_x
    and #$FF00
    lsr
    lsr
    sta tmp1
    lda text_x
    and #$00FE
    ora tmp1
    tax
    lda 1,s
    lsr
    lsr
    lsr
    lsr
    jsr hr_nib16
    sta tmp1                ; first digit, 2g
    pla
    and #$000F
    jsr hr_nib16
    pha                     ; second digit, 2g
    lda text_x
    lsr
    bcs @odd
    lda tmp1                ; x even: digit 1 even layer, digit 2 odd
    clc                     ; layer at the same entry
    adc.w hr_tab,y
    sta.w SHADOW_BG3,x
    pla
    clc
    adc.w hr_tab + 2,y
    sta.w SHADOW_HRB,x
    bra @out
@odd:
    lda tmp1                ; x odd: digit 1 odd layer, digit 2 even
    clc                     ; layer one entry right
    adc.w hr_tab + 2,y
    sta.w SHADOW_HRB,x
    pla
    clc
    adc.w hr_tab,y
    sta.w SHADOW_BG3 + 2,x
@out:
    sep #$20
.ACCU 8
    inc text_x
    inc text_x
    ply
    rts

; A16 = nibble 0-15 -> 2 * glyph index
hr_nib16:
.ACCU 16
    cmp #10
    bcc +
    adc #6
+
    adc #'0' - 32
    asl
    rts
.ACCU 8

; hex nibble A8 (0-15) -> tile index
hr_nib:
    cmp #10
    bcc +
    adc #6
+
    adc #'0' - 32
    rts

hr_puttile:
    jsr hr_put
    rtl

hr_hex8:
    jsr hr_x2
    rtl

; X = NUL-terminated string in bank $80
hr_puts:
@loop:
    lda.w $0000,x
    beq @done
    cmp #'a'
    bcc +
    sbc #32                 ; fold lowercase
+
    sec
    sbc #32
    phx
    jsr hr_put
    plx
    inx
    bra @loop
@done:
    rtl

; local helpers for bank-7 screen code (jsr, not jsl)
hr_s:                       ; X = string in this bank
    phb
    phk
    plb                     ; DB = $87: still mirrors low WRAM
    jsr @loop
    plb
    rts
@loop:
    lda.w $0000,x
    beq +
    sec
    sbc #32
    phx
    jsr hr_put
    plx
    inx
    bra @loop
+
    rts

hr_attr:                    ; A16 = attr (call in A16), returns A8
.ACCU 16
    sta text_attr
    sep #$20
.ACCU 8
    rts

hr_dash2:
    lda #'-' - 32
    jsr hr_put
    lda #'-' - 32
    jmp hr_put

; --- SONG at 64 columns ------------------------------------------------------
; layout: row label x1, track t marker at x = 4 + t*4 then the chain id,
; chain panel (the cursor cell's chain) at x = 38. The status and minimap
; chrome moves to x 59-63 via ui_xoff.
.DEFINE HS_COL0  4
.DEFINE HS_CHX   38
.DEFINE HS_PHX   47

song_hr_init:
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    jsr hr_attr
.ACCU 8
    stz text_x
    lda #1
    sta text_y
    ldx #str_hr_song
    jsr hr_s
    ; track numbers above each column
    stz ui_cnt
@heads:
    lda ui_cnt
    asl
    asl
    clc
    adc #HS_COL0 + 1
    sta text_x
    lda #3
    sta text_y
    lda ui_cnt
    clc
    adc #'1' - 32
    jsr hr_put
    inc ui_cnt
    lda ui_cnt
    cmp #TRACKS
    bne @heads
    ; chain panel captions
    lda #HS_CHX
    sta text_x
    lda #3
    sta text_y
    ldx #str_hr_chain
    jsr hr_s
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr hr_attr
.ACCU 8
    lda #HS_CHX
    sta text_x
    lda #4
    sta text_y
    ldx #str_hr_ruler
    jsr hr_s
    ; phrase preview captions
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    jsr hr_attr
.ACCU 8
    lda #HS_PHX
    sta text_x
    lda #3
    sta text_y
    ldx #str_hr_phrase
    jsr hr_s
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr hr_attr
.ACCU 8
    lda #HS_PHX
    sta text_x
    lda #4
    sta text_y
    ldx #str_hr_phruler
    jsr hr_s
    rtl

song_hr_draw:
    phy
    jsr @body
    ply
    rtl
@body:
    stz tmp0 + 1            ; visible row
@rows:
    lda tmp0 + 1
    clc
    adc #5
    sta text_y
    lda #1
    sta text_x
    ; row label: bright on every 4th row (the beat), dim otherwise
    lda song_top
    clc
    adc tmp0 + 1
    pha
    and #$03
    rep #$20
.ACCU 16
    beq @beat
    lda #ATTR_DIM
    bra @lab
@beat:
    lda #ATTR_HILITE
@lab:
    jsr hr_attr
.ACCU 8
    pla
    jsr hr_x2
    stz tmp0                ; track
    rep #$30
.ACCU 16
    lda text_y
    and #$00FF
    asl
    asl
    asl
    asl
    asl
    asl
    clc
    adc #HS_COL0             ; + (x>>1)*2 for x = 4: the first marker
    sta hr_row
    sep #$20
.ACCU 8
@cells:
    ; one position per cell: the marker sits on the even layer at
    ; x = 4+4t, the chain id's first digit on the odd layer of the same
    ; entry and its second digit on the even layer of the next one
    jsl song_head_glyph_l   ; A8 = marker tile index
    rep #$30
.ACCU 16
    and #$00FF
    asl
    clc
    adc.w hr_tab + 5 * 4    ; GREEN, even layer
    sta tmp1
    lda tmp0
    and #$00FF
    asl
    asl
    clc
    adc hr_row
    tax
    stx hr_e
    lda tmp1
    sta.w SHADOW_BG3,x
    sep #$20
.ACCU 8
    ; palette (Y = palette * 4): cursor ACCENT, else TEXT; block mode
    ; takes the full classic rules
    lda blk_mode
    beq @fast
    jsl song_cell_attr_l
    rep #$20
.ACCU 16
    lda text_attr
    xba
    and #$001C
    tay
    sep #$20
.ACCU 8
    bra @val
@fast:
    ldy #$0000
    lda tmp0
    cmp song_cx
    bne @val
    lda song_top
    clc
    adc tmp0 + 1
    cmp song_cy
    bne @val
    ldy #$0004
@val:
    rep #$30
.ACCU 16
    lda tmp0
    and #$00FF
    xba
    lsr                     ; track*128
    sta tmp2
    lda song_top
    and #$00FF
    clc
    adc tmp2
    sta tmp2
    lda tmp0 + 1
    and #$00FF
    clc
    adc tmp2
    tax
    lda.l $7E0000 + SB_SONG,x
    and #$00FF
    cmp #$00FF
    bne @hex
    cpy #$0000
    bne +
    ldy #$000C              ; empty cells recede (cursor/block keep theirs)
+
    lda #('-' - 32) * 2
    sta tmp1
    bra @put
@hex:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr hr_nib16
    sta tmp1
    pla
    and #$000F
    jsr hr_nib16
@put:
    ldx hr_e
    clc
    adc.w hr_tab,y          ; second digit: even layer, next entry
    sta.w SHADOW_BG3 + 2,x
    lda tmp1
    clc
    adc.w hr_tab + 2,y      ; first digit: odd layer, this entry
    sta.w SHADOW_HRB,x
    sep #$20
.ACCU 8
@next:
    inc tmp0
    lda tmp0
    cmp #TRACKS
    beq +
    jmp @cells
+
    inc tmp0 + 1
    lda tmp0 + 1
    cmp #16
    beq @panel
    jmp @rows
@panel:
    ; --- chain panel: the chain under the cursor ---
    rep #$30
.ACCU 16
    lda song_cx
    and #$00FF
    xba
    lsr
    sta tmp2
    lda song_cy
    and #$00FF
    clc
    adc tmp2
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_SONG,x
    cmp hr_lastch
    bne +
    rts                     ; same chain as last frame: panel unchanged
+
    sta hr_lastch
    sta tmp2                ; chain id ($FF none)
    lda #HS_CHX + 6
    sta text_x
    lda #3
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_CYAN
    jsr hr_attr
.ACCU 8
    lda tmp2
    cmp #$FF
    bne +
    jsr hr_dash2
    bra @steps
+
    jsr hr_x2
@steps:
    stz tmp0                ; preview_step = 0 default
    lda tmp2                ; chain id ($FF if none)
    cmp #$FF
    beq @do_steps
    lda chain_cy
    cmp #16
    bcs @do_steps
    rep #$30
.ACCU 16
    and #$00FF
    asl                     ; chain_cy * 2
    sta tmp1
    lda tmp2
    and #$00FF
    asl
    asl
    asl
    asl
    asl                     ; chain * 32
    clc
    adc tmp1
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_CHAINS,x
    cmp #$FF
    beq @do_steps
    lda chain_cy
    sta tmp0                ; preview_step = chain_cy
@do_steps:
    stz tmp0 + 1
@step:
    lda tmp0 + 1
    clc
    adc #5
    sta text_y
    lda #HS_CHX
    sta text_x
    lda tmp0 + 1
    cmp tmp0                ; step == preview_step?
    rep #$20
.ACCU 16
    beq +
    lda #ATTR_DIM
    bra ++
+
    lda #ATTR_HILITE
++
    jsr hr_attr
.ACCU 8
    lda tmp0 + 1
    jsr hr_nib
    jsr hr_put
    inc text_x
    lda tmp2
    cmp #$FF
    beq @nochain
    ; X = SB_CHAINS + chain*32 + step*2
    rep #$30
.ACCU 16
    lda tmp2
    and #$00FF
    asl
    asl
    asl
    asl
    asl
    sta tmp1
    lda tmp0 + 1
    and #$00FF
    asl
    clc
    adc tmp1
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_CHAINS,x
    cmp #$FF
    beq @nochain
    pha
    rep #$20
.ACCU 16
    lda #ATTR_CYAN
    jsr hr_attr
.ACCU 8
    pla
    phx
    jsr hr_x2
    plx
    inc text_x
    lda.l $7E0000 + SB_CHAINS + 1,x
    pha
    rep #$20
.ACCU 16
    lda #ATTR_PINK
    jsr hr_attr
.ACCU 8
    pla
    bne +
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr hr_attr
.ACCU 8
    lda #0
+
    jsr hr_x2
    bra @stepnext
@nochain:
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr hr_attr
.ACCU 8
    jsr hr_dash2
    inc text_x
    jsr hr_dash2
@stepnext:
    inc tmp0 + 1
    lda tmp0 + 1
    cmp #16
    beq +
    jmp @step
+
    ; --- phrase preview panel (x47..58) ---
    lda tmp2                ; chain id ($FF if none)
    cmp #$FF
    bne +
    lda #$FF
    sta tmp2 + 1            ; no chain -> no phrase ($FF)
    bra @ph_hdr
+
    ; Look up phrase at preview_step (tmp0)
    rep #$30
.ACCU 16
    lda tmp0
    and #$00FF
    asl                     ; step * 2
    sta tmp1
    lda tmp2
    and #$00FF
    asl
    asl
    asl
    asl
    asl                     ; chain * 32
    clc
    adc tmp1
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_CHAINS,x
    sta tmp2 + 1            ; phrase id ($FF if none)

@ph_hdr:
    ; Phrase ID on row 3 at HS_PHX + 7 (x=54)
    lda #HS_PHX + 7
    sta text_x
    lda #3
    sta text_y
    lda tmp2 + 1
    cmp #$FF
    bne +
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr hr_attr
.ACCU 8
    jsr hr_dash2
    bra @ph_steps
+
    pha
    rep #$20
.ACCU 16
    lda #ATTR_CYAN
    jsr hr_attr
.ACCU 8
    pla
    jsr hr_x2

@ph_steps:
    stz tmp0 + 1            ; phrase row 0..15
@ph_row:
    lda tmp0 + 1
    clc
    adc #5
    sta text_y
    lda #HS_PHX
    sta text_x
    lda tmp2 + 1            ; phrase id
    cmp #$FF
    bne @ph_row_data
    ; empty phrase: clear 12 columns with blank spaces
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr hr_attr
.ACCU 8
    ldx #str_hr_blank12
    jsr hr_s
    jmp @ph_stepnext2

@ph_row_data:
    ; 1. Row label (2 hex digits in ATTR_DIM)
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr hr_attr
.ACCU 8
    lda tmp0 + 1
    jsr hr_x2
    lda #0                  ; space (' ' - 32)
    jsr hr_put

    ; Fetch 4 bytes of phrase row into str_buf + 32..35
    lda tmp0 + 1            ; 8-bit row (0..15)
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl                     ; row * 4
    sta tmp1
    lda tmp2
    xba
    and #$00FF              ; phrase id
    asl
    asl
    asl
    asl
    asl
    asl                     ; phrase * 64
    clc
    adc tmp1
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_PHRASES,x
    sta str_buf + 32
    lda.l $7E0000 + SB_PHRASES + 1,x
    sta str_buf + 33
    lda.l $7E0000 + SB_PHRASES + 2,x
    sta str_buf + 34
    lda.l $7E0000 + SB_PHRASES + 3,x
    sta str_buf + 35

    ; 2. Note (3 chars via draw_note_l)
    lda str_buf + 32
    pha
    rep #$20
.ACCU 16
    bne +
    lda #ATTR_DIM
    bra ++
+
    lda #ATTR_TEXT
++
    jsr hr_attr
.ACCU 8
    pla
    jsl draw_note_l
    lda #0                  ; space
    jsr hr_put

    ; 3. Instrument (2 hex digits or -- in ATTR_DIM)
    lda str_buf + 33
    cmp #INSTR_NONE
    bne +
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr hr_attr
.ACCU 8
    jsr hr_dash2
    bra ++
+
    pha
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    jsr hr_attr
.ACCU 8
    pla
    jsr hr_x2
++
    lda #0                  ; space
    jsr hr_put

    ; 4. Command letter (A..Z in ATTR_PINK or - in ATTR_DIM)
    lda str_buf + 34
    beq +
    pha
    rep #$20
.ACCU 16
    lda #ATTR_PINK
    jsr hr_attr
.ACCU 8
    pla
    clc
    adc #'A' - 32 - 1       ; 1..26 -> A..Z
    jsr hr_put
    bra ++
+
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr hr_attr
.ACCU 8
    lda #'-' - 32
    jsr hr_put
++
    lda #0                  ; space
    jsr hr_put

@ph_stepnext2:
    inc tmp0 + 1
    lda tmp0 + 1
    cmp #16
    beq +
    jmp @ph_row
+
    rts

str_hr_song:    .DB "SONG", 0
str_hr_chain:   .DB "CHAIN", 0
str_hr_ruler:   .DB "  PH TSP", 0
str_hr_phrase:  .DB "PHRASE", 0
str_hr_phruler: .DB "  NOTE IN C ", 0
str_hr_blank12: .DB "            ", 0

; --- OPTIONS HI-RES (field 7): B + left/right toggles, persists at $000D ---
opt_hires_edit:
    rep #$20
.ACCU 16
    lda pad_event
    and #(PAD_LEFT | PAD_RIGHT)
    sep #$20
.ACCU 8
    beq @done
    lda #$01
    sta b_used
    lda opt_hires
    eor #$01
    sta opt_hires
    lda.l $700000
    cmp #'S'
    bne @done
    lda opt_hires
    sta.l $70000D
@done:
    rtl

; --- hi-res status bar (SONG and FRAME, row 1) -------------------------------
; Shows: song name (8 chars), tempo (T + decimal 3 digits, 0->150),
; transport state (PLAY in ATTR_PLAY, WAIT in ATTR_ACCENT, STOP in ATTR_DIM),
; and ARAM used / free (matching echoscr.asm: used = res_cursor - $1200,
; free = echo floor - res_cursor).
; SONG: starts at x=6, FRAME: starts at x=21.
; Free space x59-63 preserved for tick counter / chrome.
; Redraws only when one of the displayed values or ui_mode changes.
; Note: clobbers tmp0/tmp2 (safe: main loop chrome does not rely on them).
hr_status_bar:
    lda ui_mode
    cmp #SCREEN_SONG
    beq +
    cmp #SCREEN_FRAME
    beq +
    rtl
+
    jsr hr_meters
    lda.w hr_sb_valid
    beq @dirty
    lda ui_mode
    cmp.w hr_sb_mode
    bne @dirty
    lda eng_playing
    cmp.w hr_sb_play
    bne @dirty
    lda sync_wait
    cmp.w hr_sb_wait
    bne @dirty
    lda.l $7E0000 + SB_HEADER + SH_BPM
    cmp.w hr_sb_bpm
    bne @dirty
    lda.l $7E0000 + SB_HEADER + SH_EDL
    cmp.w hr_sb_edl
    bne @dirty
    rep #$20
.ACCU 16
    lda res_cursor
    cmp.w hr_sb_cursor
    bne @dirty16
    lda.l $7E0000 + SB_HEADER + SH_NAME
    cmp.w hr_sb_name
    bne @dirty16
    lda.l $7E0000 + SB_HEADER + SH_NAME + 2
    cmp.w hr_sb_name + 2
    bne @dirty16
    lda.l $7E0000 + SB_HEADER + SH_NAME + 4
    cmp.w hr_sb_name + 4
    bne @dirty16
    lda.l $7E0000 + SB_HEADER + SH_NAME + 6
    cmp.w hr_sb_name + 6
    bne @dirty16
    sep #$20
.ACCU 8
    rtl

@dirty16:
    sep #$20
.ACCU 8
@dirty:
    ; snapshot
    lda ui_mode
    sta.w hr_sb_mode
    lda eng_playing
    sta.w hr_sb_play
    lda sync_wait
    sta.w hr_sb_wait
    lda.l $7E0000 + SB_HEADER + SH_BPM
    sta.w hr_sb_bpm
    lda.l $7E0000 + SB_HEADER + SH_EDL
    sta.w hr_sb_edl
    rep #$20
.ACCU 16
    lda res_cursor
    sta.w hr_sb_cursor
    lda.l $7E0000 + SB_HEADER + SH_NAME
    sta.w hr_sb_name
    lda.l $7E0000 + SB_HEADER + SH_NAME + 2
    sta.w hr_sb_name + 2
    lda.l $7E0000 + SB_HEADER + SH_NAME + 4
    sta.w hr_sb_name + 4
    lda.l $7E0000 + SB_HEADER + SH_NAME + 6
    sta.w hr_sb_name + 6
    sep #$20
.ACCU 8
    lda #$01
    sta.w hr_sb_valid

    ; coordinates: y=1, x=6 (SONG) or x=21 (FRAME)
    lda #1
    sta text_y
    lda ui_mode
    cmp #SCREEN_FRAME
    beq +
    lda #6
    bra ++
+
    lda #21
++
    sta text_x

    ; 1. Song name (8 chars, ATTR_TEXT)
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    jsr hr_attr
.ACCU 8
    ldy #0
@name_loop:
    tyx
    lda.l $7E0000 + SB_HEADER + SH_NAME,x
    cmp #' '
    bcs +
    lda #' '
+
    sec
    sbc #32
    jsr hr_put
    iny
    cpy #8
    bne @name_loop

    ; 1 space
    lda #0
    jsr hr_put

    ; 2. Tempo (T in ATTR_DIM, 3 digits in ATTR_TEXT)
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr hr_attr
.ACCU 8
    lda #'T' - 32
    jsr hr_put
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    jsr hr_attr
.ACCU 8
    lda.l $7E0000 + SB_HEADER + SH_BPM
    bne +
    lda #150
+
    jsr hr_dec3

    ; 1 space
    lda #0
    jsr hr_put

    ; 3. Play state (4 chars: PLAY / WAIT / STOP)
    lda eng_playing
    beq @st_stop
    lda sync_wait
    bne @st_wait
    rep #$20
.ACCU 16
    lda #ATTR_PLAY
    jsr hr_attr
.ACCU 8
    ldx #str_hr_play
    jsr hr_s
    bra @st_done
@st_wait:
    rep #$20
.ACCU 16
    lda #ATTR_ACCENT
    jsr hr_attr
.ACCU 8
    ldx #str_hr_wait
    jsr hr_s
    bra @st_done
@st_stop:
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr hr_attr
.ACCU 8
    ldx #str_hr_stop
    jsr hr_s
@st_done:

    ; 1 space
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr hr_attr
.ACCU 8
    lda #0
    jsr hr_put

    ; 4. ARAM used / free (ATTR_DIM)
    ldx #str_hr_ram
    jsr hr_s

    ; used = res_cursor - $1200
    rep #$30
.ACCU 16
    lda res_cursor
    sec
    sbc #$1200
    sta tmp0
    sep #$20
.ACCU 8
    jsr hr_fl_kb

    lda ui_mode
    cmp #SCREEN_FRAME
    beq @f_frame
    ldx #str_hr_free
    jsr hr_s
    bra @calc_free
@f_frame:
    ldx #str_hr_ffree
    jsr hr_s

@calc_free:
    ; free = echo floor - resident end; floor page = $100 - 8*EDL
    lda.l $7E0000 + SB_HEADER + SH_EDL
    and #$0F
    asl
    asl
    asl
    eor #$FF
    inc a
    bne @floor_ok
    lda #$FF
@floor_ok:
    rep #$30
.ACCU 16
    and #$00FF
    xba                     ; floor page -> byte address
    sec
    sbc res_cursor
    bcs @free_ok
    lda #$0000
@free_ok:
    sta tmp0
    sep #$20
.ACCU 8
    jsr hr_fl_kb

    rtl

; print A (0-255) as 3 decimal digits via hr_put
hr_dec3:
    ldx #0
@h:
    cmp #100
    bcc @h_done
    sec
    sbc #100
    inx
    bra @h
@h_done:
    pha
    txa
    clc
    adc #'0' - 32
    jsr hr_put
    pla
    ldx #0
@t:
    cmp #10
    bcc @t_done
    sec
    sbc #10
    inx
    bra @t
@t_done:
    pha
    txa
    clc
    adc #'0' - 32
    jsr hr_put
    pla
    clc
    adc #'0' - 32
    jmp hr_put

; print tmp0 (16-bit bytes) as "NN.NK" via hr_put (5 chars)
hr_fl_kb:
    rep #$30
.ACCU 16
    lda tmp0
    and #$03FF
    sta tmp2
    lda tmp0
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr                     ; whole KB (0-63)
    sta tmp0
    sep #$20
.ACCU 8
    lda tmp0
    ldy #$0000
@tens:
    cmp #10
    bcc @tens_done
    sec
    sbc #10
    iny
    bra @tens
@tens_done:
    pha
    rep #$30
.ACCU 16
    tya
    sep #$20
.ACCU 8
    beq @no_tens
    clc
    adc #'0' - 32
    jsr hr_put
    bra @unit
@no_tens:
    lda #0                  ; tile 0 = space
    jsr hr_put
@unit:
    pla
    clc
    adc #'0' - 32
    jsr hr_put
    lda #'.' - 32
    jsr hr_put
    ; decimal = (rem * 10) >> 10
    rep #$30
.ACCU 16
    lda tmp2
    asl
    asl
    asl
    clc
    adc tmp2
    clc
    adc tmp2                ; * 10
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr
    sep #$20
.ACCU 8
    clc
    adc #'0' - 32
    jsr hr_put
    lda #'K' - 32
    jmp hr_put

str_hr_play:  .DB "PLAY", 0
str_hr_wait:  .DB "WAIT", 0
str_hr_stop:  .DB "STOP", 0
str_hr_ram:   .DB "RAM ", 0
str_hr_free:  .DB " FREE ", 0
str_hr_ffree: .DB " F ", 0

; value cell: text_x/y/attr already set by options_draw (classic screen)
opt_hires_draw:
    ldx #str_o_on
    lda opt_hires
    bne +
    ldx #str_o_off
+
    phb
    phk
    plb
    jsl text_puts_l
    plb
    rtl

str_o_on:  .DB "ON ", 0
str_o_off: .DB "OFF", 0

; per palette p: even-layer base, odd-layer base (word + 2g = the entry).
; Priority set; ACCENT (1) and PLAY (4) use the inverted glyphs (+192
; tiles); the odd layer stores palettes 1 and 4 swapped.
hr_tab_rom:
    .DW $2001, $2000             ; 0 TEXT
    .DW $2400 + 193, $3000 + 192 ; 1 ACCENT (inverted; odd layer pal 4)
    .DW $2801, $2800             ; 2 HILITE
    .DW $2C01, $2C00             ; 3 DIM
    .DW $3000 + 193, $2400 + 192 ; 4 PLAY (inverted; odd layer pal 1)
    .DW $3401, $3400             ; 5 GREEN
    .DW $3801, $3800             ; 6 CYAN
    .DW $3C01, $3C00             ; 7 PINK


; --- level meters (hi-res SONG and FRAME, row 4) -----------------------------
; Draws 1-cell meter per voice (tracks 0-7) using GLYPH_BLOCK14/12/34/BLOCK
; in ATTR_GREEN. Redraws only meters whose quantised level (0-4) changed.
; Hi-res SONG: y=4, x = 5 + t*4 (under each track number)
; Hi-res FRAME: y=4, x = 7 + t*7 (cell after phrase id)
song_meter_x: .DB 5, 9, 13, 17, 21, 25, 29, 33
fr_meter_x:   .DB 7, 14, 21, 28, 35, 42, 49, 56
meter_glyphs: .DB 0, GLYPH_BLOCK14, GLYPH_BLOCK12, GLYPH_BLOCK34, GLYPH_BLOCK

hr_meters:
    lda ui_mode
    cmp #SCREEN_SONG
    beq @screen_ok
    cmp #SCREEN_FRAME
    beq @screen_ok
    lda #$FF
    sta.w hr_meter_scr
    rts
@screen_ok:
    cmp.w hr_meter_scr
    beq @check_full
    ; screen changed: invalidate all 8 meter levels
    sta.w hr_meter_scr
    ldx #7
-
    lda #$FF
    sta.w hr_meter_lvl,x
    dex
    bpl -
@check_full:
    ; On FRAME, if full redraw was requested, invalidate all meters
    lda ui_mode
    cmp #SCREEN_FRAME
    bne @do_meters
    lda fr_full
    beq +
    ldx #7
-
    lda #$FF
    sta.w hr_meter_lvl,x
    dex
    bpl -
+
    ; If cursor moved on FRAME, invalidate fr_t and fr_oldtrk
    rep #$20
.ACCU 16
    lda fr_input
    sep #$20
.ACCU 8
    beq @do_meters
    lda fr_t
    cmp #TRACKS
    bcs +
    rep #$20
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda #$FF
    sta.w hr_meter_lvl,x
+
    lda fr_oldtrk
    cmp #TRACKS
    bcs +
    rep #$20
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda #$FF
    sta.w hr_meter_lvl,x
+

@do_meters:
    ldy #0                  ; track counter t = 0..7
@loop:
    tyx
    lda eng_playing
    beq @lvl_zero
    lda.w envx_mirror,x
    beq @lvl_zero
    lsr
    lsr
    lsr
    lsr
    lsr                     ; 0..3 (1..31 -> 0, 32..63 -> 1, 64..95 -> 2, 96..127 -> 3)
    inc a                   ; 1..4
    bra @got_lvl
@lvl_zero:
    lda #0
@got_lvl:
    cmp.w hr_meter_lvl,x
    beq @next
    sta.w hr_meter_lvl,x

    ; Look up glyph for new level (0..4)
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.l meter_glyphs,x
    pha                     ; save glyph on stack

    ; Position: text_y = 4, text_x from table
    lda #4
    sta text_y
    tyx                     ; restore X = track 0..7 from Y
    lda ui_mode
    cmp #SCREEN_SONG
    bne +
    lda.l song_meter_x,x
    bra ++
+
    lda.l fr_meter_x,x
++
    sta text_x

    ; Attribute: ATTR_GREEN
    rep #$20
.ACCU 16
    lda #ATTR_GREEN
    jsr hr_attr
.ACCU 8

    ; Draw glyph
    pla                     ; restore glyph
    jsr hr_put

@next:
    iny
    cpy #TRACKS
    bne @loop
    rts

; --- G6: Beat-row HDMA tint (SONG and FRAME screens in Mode 5) ----------------
; Tints every 4th grid row darker by updating CGRAM 0 and COLDATA via HDMA.
; Grid starts at row y=5 (scanline 40). In Mode 5, main screen backdrop is
; CGRAM 0, and sub screen backdrop is COLDATA. Both must be updated simultaneously
; to avoid vertical striping.
; Channels:
;   Channel 1: writes $00 to $2121 (CGADD)
;   Channel 2: writes 2 bytes (low, high) to $2122 (CGDATA)
;   Channel 3: writes 2 bytes ($20/21, $C1/C2) to $2132 (COLDATA)
; HDMAEN: $0E (bits 1, 2, 3)

.DEFINE HDMA_NORM_COL  $0841
.DEFINE HDMA_DARK_COL  $0420
.DEFINE HDMA_NORM_CD1  $21
.DEFINE HDMA_NORM_CD2  $C2
.DEFINE HDMA_DARK_CD1  $20
.DEFINE HDMA_DARK_CD2  $C1

hr_hdma_nmi:
    lda ui_mode
    cmp #SCREEN_SONG
    beq @active
    cmp #SCREEN_FRAME
    beq @active
    stz HDMAEN
    stz CGADD
    lda #$41
    sta CGDATA
    lda #$08
    sta CGDATA
    rts
@active:
    rep #$20
.ACCU 16
    lda #$2100              ; DMAP1 = mode 0 (1 reg, 1 byte), BBAD1 = $21 (CGADD)
    sta DMAP1
    lda #$2202              ; DMAP2 = mode 2 (1 reg, 2 bytes), BBAD2 = $22 (CGDATA)
    sta DMAP2
    lda #$3202              ; DMAP3 = mode 2 (1 reg, 2 bytes), BBAD3 = $32 (COLDATA)
    sta DMAP3
    sep #$20
.ACCU 8
    lda #$07                ; Bank 7
    sta A1B1
    sta A1B2
    sta A1B3

    ; Phase 0..3: FRAME is always phase 0; SONG is song_top & 3
    lda #0
    ldx ui_mode
    cpx #SCREEN_FRAME
    beq +
    lda song_top
    and #$03
+
    rep #$30
.ACCU 16
.INDEX 16
    and #$0003
    asl
    tax
    lda.l hdma_cgadd_ptrs,x
    sta A1T1L
    lda.l hdma_cgdata_ptrs,x
    sta A1T2L
    lda.l hdma_coldata_ptrs,x
    sta A1T3L
    sep #$20
.ACCU 8
    lda #$0E                ; Enable HDMA channels 1, 2, 3
    sta HDMAEN
    rts

; --- Phase 0: beat row at grid row 0 (y=5, scanline 40) ---
hdma_cgadd_p0:
    .DB 40, $00
    .DB 8,  $00
    .DB 24, $00
    .DB 8,  $00
    .DB 24, $00
    .DB 8,  $00
    .DB 24, $00
    .DB 8,  $00
    .DB 80, $00
    .DB 0

hdma_cgdata_p0:
    .DB 40
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 24
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 24
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 24
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 80
    .DW HDMA_NORM_COL
    .DB 0

hdma_coldata_p0:
    .DB 40, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 24, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 24, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 24, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 80, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 0

; --- Phase 1: beat row at grid row 3 (y=8, scanline 64) ---
hdma_cgadd_p1:
    .DB 64, $00
    .DB 8,  $00
    .DB 24, $00
    .DB 8,  $00
    .DB 24, $00
    .DB 8,  $00
    .DB 24, $00
    .DB 8,  $00
    .DB 56, $00
    .DB 0

hdma_cgdata_p1:
    .DB 64
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 24
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 24
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 24
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 56
    .DW HDMA_NORM_COL
    .DB 0

hdma_coldata_p1:
    .DB 64, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 24, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 24, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 24, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 56, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 0

; --- Phase 2: beat row at grid row 2 (y=7, scanline 56) ---
hdma_cgadd_p2:
    .DB 56, $00
    .DB 8,  $00
    .DB 24, $00
    .DB 8,  $00
    .DB 24, $00
    .DB 8,  $00
    .DB 24, $00
    .DB 8,  $00
    .DB 64, $00
    .DB 0

hdma_cgdata_p2:
    .DB 56
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 24
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 24
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 24
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 64
    .DW HDMA_NORM_COL
    .DB 0

hdma_coldata_p2:
    .DB 56, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 24, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 24, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 24, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 64, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 0

; --- Phase 3: beat row at grid row 1 (y=6, scanline 48) ---
hdma_cgadd_p3:
    .DB 48, $00
    .DB 8,  $00
    .DB 24, $00
    .DB 8,  $00
    .DB 24, $00
    .DB 8,  $00
    .DB 24, $00
    .DB 8,  $00
    .DB 72, $00
    .DB 0

hdma_cgdata_p3:
    .DB 48
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 24
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 24
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 24
    .DW HDMA_NORM_COL
    .DB 8
    .DW HDMA_DARK_COL
    .DB 72
    .DW HDMA_NORM_COL
    .DB 0

hdma_coldata_p3:
    .DB 48, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 24, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 24, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 24, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 8,  HDMA_DARK_CD1, HDMA_DARK_CD2
    .DB 72, HDMA_NORM_CD1, HDMA_NORM_CD2
    .DB 0

hdma_cgadd_ptrs:
    .DW hdma_cgadd_p0, hdma_cgadd_p1, hdma_cgadd_p2, hdma_cgadd_p3
hdma_cgdata_ptrs:
    .DW hdma_cgdata_p0, hdma_cgdata_p1, hdma_cgdata_p2, hdma_cgdata_p3
hdma_coldata_ptrs:
    .DW hdma_coldata_p0, hdma_coldata_p1, hdma_coldata_p2, hdma_coldata_p3

hr_pal:
    .INCBIN "hrpal.bin"
hr_font2:
    .INCBIN "hrfont2.bin"
hr_font2_end:
hr_font4:
    .INCBIN "hrfont4.bin"
hr_font4_end:

.ENDS
