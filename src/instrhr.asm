; instrhr.asm — the hi-res INSTR screen's graphics panel (UI rewrite,
; branch ui-instr). Bank 8; WRAM $0DE0-$0DFF (work split with Gemini).
;
; With OPTIONS HI-RES on, INSTR keeps its classic field list (it draws
; through text_* into columns 0-31, the left half of the 64-column
; screen) and gains a panel on the right:
;   rows 7-14   the sample's waveform (SMP/SLICE: the pool sample;
;               WAV: the wave bank), its name, size and loop point
;   rows 16-19  the volume envelope drawn from ATTACK/DECAY/SUS LVL/
;               SUS RATE (types that use the DSP ADSR)
;
; The graphics are bitmaps in dedicated BG2 (2bpp, even-column layer)
; tiles: each tilemap entry is 16 hi-res pixels = tile N (left) + N+1
; (right), so a 12-entry x R-row region needs 24*R unique tiles. They're
; drawn in a WRAM buffer in bank $7F and uploaded by the NMI in 512-byte
; chunks (ih_nmi, called from nmi_hr), so VBlank stays inside budget.
;
; Drawing is spread over frames (ih_frame, one step per frame from
; instr_update) so a nudge never costs the engine a frame: the main loop
; also runs the sequencer. Steps: waveform = begin + 8 parts + info,
; envelope = begin + 3 segments; the upload starts when both are done.
;
; The waveform shapes come from build/peaks.bin (tools/makepeaks.py): the
; build decodes each pool sample once; decoding BRR here would take many
; frames.

.ENUM $0DE0
ih_jobs   db          ; bit 1 = waveform pending, bit 0 = envelope pending
ih_wkey   ds 3        ; waveform key: instrument, type, sample byte
ih_akey   ds 3        ; envelope key: type, ADSR1, ADSR2
ih_len    dw          ; NMI upload: bytes left
ih_src    dw          ; NMI upload: source offset in bank $7F (also the
                      ; peaks/wave offset while a waveform job runs:
                      ; uploads only start once every job is done)
ih_dst    dw          ; NMI upload: VRAM word address
ih_x      db          ; plot: x (0-191)
ih_ya     db          ; plot: first row
ih_yb     db          ; plot: last row
ih_mask   db          ; plot: pixel bits within the byte
ih_step   db          ; step of the running job
ih_kind   db          ; waveform: 0 none, 1 pool sample, 2 wave bank
ih_base   dw          ; plot: buffer offset of the graphic
ih_i      db          ; loop counter
ih_t      db          ; scratch
ih_acc    dw          ; line: 8.8 y accumulator
ih_slope  dw          ; line: 8.8 |dy| per column
ih_px1    db          ; envelope: x at the attack peak
ih_px2    db          ; envelope: x where decay meets the sustain level
ih_ysl    db          ; envelope: y of the sustain level
ih_yend   db          ; envelope: y at the right edge
.ENDE                 ; ends $0DFF

.DEFINE IH_T0       400                      ; first BG2 tile used
.DEFINE IH_WTILES   96                       ; 12 entries x 4 rows x 2
.DEFINE IH_T1       (IH_T0 + IH_WTILES)      ; envelope tiles (72)
.DEFINE IH_VRAM     (VRAM_HR_BG2_CHR + IH_T0 * 8)
.DEFINE IH_WBYTES   (IH_WTILES * 16)         ; 1536
.DEFINE IH_ABYTES   (72 * 16)                ; 1152
.DEFINE IH_X        34                       ; panel text column
.DEFINE IH_ENTRY    (IH_X / 2)               ; = 17
.DEFINE IH_WROW     9                        ; waveform rows 9-12
.DEFINE IH_AROW     17                       ; envelope rows 17-19
.DEFINE IH_BUF      $7F0000                  ; waveform; envelope at +$600

.BANK 8 SLOT 0
.SECTION "INSTR hi-res panel" FREE

.ACCU 8
.INDEX 16

; --- screen entry (after hr_enter) -----------------------------------------------
ih_enter:
    lda #$03
    sta ih_jobs             ; draw both graphics
    stz ih_step
    rep #$30
.ACCU 16
    stz ih_len
    ; graphic tilemap entries on the even layer: row r, entry e ->
    ; tiles base + (r*12 + e)*2, palette 6 (cyan) / 5 (green), priority
    lda #$3800 | IH_T0
    sta ih_src              ; (scratch here: the next tile word)
    ldx #(IH_WROW * 64 + IH_ENTRY * 2)
    ldy #4
    jsr @rows
    lda #$3400 | IH_T1
    sta ih_src
    ldx #(IH_AROW * 64 + IH_ENTRY * 2)
    ldy #3
    jsr @rows
    stz ih_src
    sep #$20
.ACCU 8
    ; captions
    lda #IH_X
    sta text_x
    lda #16
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_ih_env
    jsr ih_puts
    rtl
.ACCU 16
@rows:                      ; X = shadow offset of the row's first entry
    phx
    lda #12
    sta ih_i                ; (16-bit store also clears ih_t: harmless)
-
    lda ih_src
    sta.w SHADOW_BG3,x
    inc a
    inc a
    sta ih_src
    inx
    inx
    dec ih_i
    bne -
    pla
    clc
    adc #64
    tax
    dey
    bne @rows
    rts
.ACCU 8

; X = string in this bank
ih_puts:
    phb
    phk
    plb
    jsl text_puts_l
    plb
    rts

; A = glyph count of spaces
ih_spaces:
    sta ih_t
-
    lda #' ' - 32
    jsl text_puttile_l
    dec ih_t
    bne -
    rts

; --- per INSTR redraw (instr_draw hook): queue what changed ------------------
ih_tick:
    lda ih_jobs
    jsr ih_active
    sta ih_t                ; the job running before this edit
    ; X = this instrument's record
    lda ed_instr
    rep #$30
.ACCU 16
    and #$003F
    asl
    asl
    asl
    asl
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_INSTR,x
    and #$07
    cmp ih_akey
    bne @adirty
    lda.l $7E0000 + SB_INSTR + 2,x
    cmp ih_akey + 1
    bne @adirty
    lda.l $7E0000 + SB_INSTR + 3,x
    cmp ih_akey + 2
    beq @wave
@adirty:
    lda.l $7E0000 + SB_INSTR,x
    and #$07
    sta ih_akey
    lda.l $7E0000 + SB_INSTR + 2,x
    sta ih_akey + 1
    lda.l $7E0000 + SB_INSTR + 3,x
    sta ih_akey + 2
    lda #$01
    jsr ih_queue
@wave:
    lda ed_instr
    cmp ih_wkey
    bne @wdirty
    lda.l $7E0000 + SB_INSTR,x
    and #$07
    cmp ih_wkey + 1
    bne @wdirty
    lda.l $7E0000 + SB_INSTR + 1,x
    cmp ih_wkey + 2
    beq @done
@wdirty:
    lda ed_instr
    sta ih_wkey
    lda.l $7E0000 + SB_INSTR,x
    and #$07
    sta ih_wkey + 1
    lda.l $7E0000 + SB_INSTR + 1,x
    sta ih_wkey + 2
    lda #$02
    jsr ih_queue
@done:
    rtl

; A = job bit: queue it; restart the running job if it is this one or if
; the running job changes
ih_queue:
    pha
    ora ih_jobs
    sta ih_jobs
    rep #$20
.ACCU 16
    stz ih_len              ; no upload while the bitmap changes
    sep #$20
.ACCU 8
    lda ih_jobs
    jsr ih_active
    cmp ih_t
    beq +
    stz ih_step             ; a different job runs now
+
    pla
    cmp ih_t
    bne +
    stz ih_step             ; the running job's input changed: restart
+
    lda ih_jobs
    jsr ih_active
    sta ih_t
    rts

; A = jobs -> A = the job that runs first (waveform before envelope), 0 none
ih_active:
    bit #$02
    beq +
    lda #$02
    rts
+
    and #$01
    rts

; --- every INSTR frame (instr_update hook): one drawing step ------------------
ih_frame:
    lda ih_jobs
    bne +
    rtl
+
    ; draw only on frames without input: an edit frame already redraws
    ; the field list (instr_draw), and the two together can overrun
    rep #$20
.ACCU 16
    lda pad_pressed
    ora pad_event
    sep #$20
.ACCU 8
    beq +
    rtl
+
    lda ih_jobs
    jsr ih_active
    cmp #$02
    beq @wave
    ; envelope: begin, then segments 1-3
    lda ih_step
    bne +
    jsr ih_env_begin
    bra @stepped
+
    jsr ih_env_seg
    lda ih_step
    cmp #4
    bne @stepped
    lda ih_jobs
    and #$FE
    bra @finished
@wave:
    lda ih_step
    bne +
    jsr ih_wave_begin
    bra @stepped
+
    cmp #9
    bcs +
    jsr ih_wave_part
    bra @stepped
+
    jsr ih_wave_info
    lda ih_jobs
    and #$FD
@finished:
    stz ih_step
    sta ih_jobs             ; (sets Z from the remaining jobs)
    bne @out
    ; all drawn: upload the panel (2688 bytes) a few chunks per frame
    rep #$20
.ACCU 16
    stz ih_src
    lda #IH_VRAM
    sta ih_dst
    lda #(IH_WBYTES + IH_ABYTES)
    sta ih_len              ; last: the NMI starts on this
    sep #$20
.ACCU 8
@out:
    rtl
@stepped:
    inc ih_step
    rtl

; --- NMI (from nmi_hr): one chunk of the pending upload -------------------------
ih_nmi:
    rep #$20
.ACCU 16
    lda ih_len
    bne +
    sep #$20
.ACCU 8
    rtl
.ACCU 16
+
    cmp #512
    bcc +
    lda #512
+
    sta DAS0L               ; (16-bit store: DAS0L/DAS0H)
    sep #$20
.ACCU 8
    lda #$80
    sta VMAIN
    ldx ih_dst
    stx VMADDL
    lda #$01
    sta DMAP0
    lda #$18
    sta BBAD0
    ldx ih_src
    stx A1T0L
    lda #$7F
    sta A1B0
    lda #$01
    sta MDMAEN
    rep #$20
.ACCU 16
    lda ih_len
    cmp #512
    bcc @last
    sec
    sbc #512
    sta ih_len
    lda ih_src
    clc
    adc #512
    sta ih_src
    lda ih_dst
    clc
    adc #256
    sta ih_dst
    sep #$20
.ACCU 8
    rtl
.ACCU 16
@last:
    stz ih_len
    sep #$20
.ACCU 8
    rtl

; --- plotting ----------------------------------------------------------------------
; clear the buffer at ih_base, A16 = byte count: DMA channel 7 streams a
; fixed zero byte into the WRAM port (channel 0 belongs to the NMI, which
; may run between these writes; nothing else uses channel 7)
ih_clear:
.ACCU 16
    sta DMAP7 + 5           ; DAS7 (16-bit store)
    lda ih_base
    sta WMADDL              ; (16-bit store: WMADDL/WMADDM)
    sep #$20
.ACCU 8
    lda #$01                ; bank $7F
    sta WMADDH
    lda #$08                ; fixed source, one register
    sta DMAP7
    lda #<WMDATA
    sta DMAP7 + 1           ; BBAD7
    ldx #zero_byte
    stx DMAP7 + 2           ; A1T7
    lda #:zero_byte
    sta DMAP7 + 4           ; A1B7
    lda #$80
    sta MDMAEN
    rts

; set colour 3 at column ih_x, rows ih_ya..ih_yb (inclusive, ya <= yb),
; bits ih_mask, in the graphic at ih_base (12 entries wide: a tile row is
; 384 bytes, see ih_rowoff). Column part = (x & $F8) * 2: x>>4 entries of
; 32 bytes plus 16 for the right tile of the pair.
ih_vspan:
    rep #$30
.ACCU 16
    lda ih_mask
    and #$00FF
    sta tmp2
    xba
    ora tmp2
    sta tmp2                ; mask in both bytes: planes 0 and 1 = colour 3
    lda ih_yb
    sec
    sbc ih_ya
    and #$00FF
    inc a
    sta tmp1                ; rows to set
    lda ih_x
    and #$00F8
    asl
    adc ih_base             ; (C clear: x*2 < $200)
    pha
    lda ih_ya
    and #$00FF
    asl
    tax
    lda.l ih_rowoff,x
    clc
    adc 1,s
    tax
    pla
    lda ih_ya
    and #$0007
    tay                     ; row within the tile
@px:
    lda.l IH_BUF,x
    ora tmp2
    sta.l IH_BUF,x
    dec tmp1
    beq @done
    iny
    cpy #8
    beq @row
    inx
    inx
    bra @px
@row:
    ldy #$0000
    txa
    clc
    adc #(384 - 14)         ; down to the next tile row
    tax
    bra @px
@done:
    sep #$20
.ACCU 8
    rts

; byte offset of pixel row y within a 12-entry graphic
ih_rowoff:
    .DW 0, 2, 4, 6, 8, 10, 12, 14
    .DW 384, 386, 388, 390, 392, 394, 396, 398
    .DW 768, 770, 772, 774, 776, 778, 780, 782
    .DW 1152, 1154, 1156, 1158, 1160, 1162, 1164, 1166

; A = x -> ih_x and ih_mask = that pixel's bit
ih_setx:
    sta ih_x
    and #$07
    rep #$30
.ACCU 16
    and #$00FF
    tax
    sep #$20
.ACCU 8
    lda.l ih_bits,x
    sta ih_mask
    rts

ih_bits: .DB $80, $40, $20, $10, $08, $04, $02, $01

; --- waveform ------------------------------------------------------------------------
; step 0: clear, captions, and which source (ih_kind) with its offset
ih_wave_begin:
    stz ih_kind
    rep #$20
.ACCU 16
    stz ih_base
    lda #IH_WBYTES
    jsr ih_clear
.ACCU 8
    ; caption row 7: WAVE + name, row 14: size / loop (blank first)
    lda #IH_X
    sta text_x
    lda #7
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_ih_wave
    jsr ih_puts
    lda #IH_X
    sta text_x
    lda #13
    sta text_y
    lda #24
    jsr ih_spaces
    lda #IH_X
    sta text_x
    lda #14
    sta text_y
    lda #24
    jsr ih_spaces
    lda #IH_X + 6
    sta text_x
    lda #7
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_CYAN
    sta text_attr
    sep #$20
.ACCU 8
    lda ih_wkey + 1         ; type
    beq @pool               ; SMP
    cmp #$04
    beq @pool               ; SLICE
    cmp #$02
    bne @none
    jmp ih_bank_begin       ; WAV
@none:
    ldx #str_ih_nosmp
    jsr ih_puts
    rts
@pool:
    lda ih_wkey + 2
    and #$3F
    cmp.l POOL_ROM + 9      ; entry count
    bcc +
    ldx #str_ih_nosmp
    jsr ih_puts
    rts
+
    sta ih_t
    ; name (8 chars from the pool directory)
    rep #$30
.ACCU 16
    and #$003F
    asl
    asl
    asl
    asl
    tax
    sep #$20
.ACCU 8
    lda #8
    sta ih_i
-
    lda.l POOL_TABLE,x
    cmp #'a'
    bcc +
    sbc #32
+
    cmp #' '
    bcs +
    lda #' '
+
    sec
    sbc #32
    phx
    jsl text_puttile_l
    plx
    inx
    dec ih_i
    bne -
    lda ih_t
    rep #$30
.ACCU 16
    and #$00FF
    sta tmp1
    asl
    clc
    adc tmp1                ; *3
    asl
    asl
    asl
    asl
    asl                     ; *96
    sta ih_src              ; peaks offset for the parts
    sep #$20
.ACCU 8
    lda #$01
    sta ih_kind
    rts

; steps 1-8: one eighth of the waveform
ih_wave_part:
    lda ih_kind
    bne +
    rts
+
    cmp #$02
    bne +
    jmp ih_bank_part
+
    ; pool: bins (step-1)*12 .. +11, 2 pixels each, centred on rows 15/16
    lda ih_step
    dec a
    sta ih_i
    asl
    clc
    adc ih_i                ; *3
    asl
    asl                     ; *12
    sta ih_i
    clc
    adc #12
    pha                     ; end bin (exclusive), on the stack
@bin:
    rep #$30
.ACCU 16
    lda ih_i
    and #$00FF
    clc
    adc ih_src
    tax
    sep #$20
.ACCU 8
    lda.l ih_peaks,x
    bne +
    lda #1                  ; silence: a 2-pixel centre line
+
    sta ih_t
    lda #16
    sec
    sbc ih_t
    sta ih_ya
    lda #15
    clc
    adc ih_t
    sta ih_yb
    lda ih_i
    asl
    jsr ih_setx
    lda ih_mask
    lsr
    ora ih_mask             ; both pixels of the bin (same byte: x even)
    sta ih_mask
    jsr ih_vspan
    inc ih_i
    lda ih_i
    cmp 1,s
    bne @bin
    pla
    rts

; last step: size and loop point (pool) / step count (wave bank)
ih_wave_info:
    lda ih_kind
    bne +
    rts
+
    cmp #$02
    bne +
    jmp ih_bank_info
+
    ; size and loop, row 14
    lda ih_wkey + 2
    and #$3F
    rep #$30
.ACCU 16
    and #$003F
    asl
    asl
    asl
    asl
    tax
    lda.l POOL_TABLE + 10,x ; length in 9-byte blocks
    sta es0
    lda.l POOL_TABLE + 12,x ; loop block ($FFFF one-shot)
    sta es0 + 2
    sep #$20
.ACCU 8
    lda #IH_X
    sta text_x
    lda #14
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    ; KB with one decimal: blocks*9*10/1024 ~= (blocks*9 >> 4) * 10 >> 6
    lda es0
    asl
    asl
    asl
    clc
    adc es0                 ; bytes
    lsr
    lsr
    lsr
    lsr
    sta tmp1
    asl
    asl
    clc
    adc tmp1
    asl                     ; *10
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr                     ; tenths of a KB
    jsr ih_dec_tenths
.ACCU 8
    ldx #str_ih_kb
    jsr ih_puts
    rep #$20
.ACCU 16
    lda es0 + 2
    cmp #$FFFF
    sep #$20
.ACCU 8
    bne @loop
    ldx #str_ih_oneshot
    jsr ih_puts
    rts
@loop:
    ldx #str_ih_loop
    jsr ih_puts
    ; percent and x: scale blocks and loop to < 256, then 8x8 / 16/8
    rep #$20
.ACCU 16
-
    lda es0
    cmp #$0100
    bcc +
    lsr es0
    lsr es0 + 2
    bra -
+
    sep #$20
.ACCU 8
    lda es0
    bne +
    rts
+
    lda es0 + 2
    sta WRMPYA
    lda #100
    sta WRMPYB
    nop
    nop
    nop
    nop
    ldx RDMPYL
    stx WRDIVL
    lda es0
    sta WRDIVB
    jsr ih_divwait
    lda RDDIVL
    rep #$20
.ACCU 16
    and #$00FF
    jsr ih_dec
.ACCU 8
    lda #'%' - 32
    jsl text_puttile_l
    ; the loop point: an up-arrow under the waveform, row 13
    lda es0 + 2
    sta WRMPYA
    lda #192
    sta WRMPYB
    nop
    nop
    nop
    nop
    ldx RDMPYL
    stx WRDIVL
    lda es0
    sta WRDIVB
    jsr ih_divwait
    lda RDDIVL              ; x 0-191
    lsr
    lsr
    lsr                     ; text column within the panel
    clc
    adc #IH_X
    sta text_x
    lda #13
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    lda #GLYPH_ARROW_U
    jsl text_puttile_l
    rts

ih_divwait:
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    rts

; WAV: the wave bank's 32 steps (0-15), 6 pixels each, 2 pixels thick
ih_bank_begin:
    ldx #str_ih_bank
    jsr ih_puts
    lda ih_wkey + 2
    and #$07
    pha
    clc
    adc #'0' - 32
    jsl text_puttile_l
    pla
    rep #$30
.ACCU 16
    and #$0007
    asl
    asl
    asl
    asl
    asl                     ; bank*32
    sta ih_src
    sep #$20
.ACCU 8
    lda #$02
    sta ih_kind
    rts

ih_bank_part:               ; columns (step-1)*24 .. +23
    lda ih_step
    dec a
    sta ih_i
    asl
    clc
    adc ih_i                ; *3
    asl
    asl
    asl                     ; *24
    sta ih_i
    clc
    adc #24
    pha
@col:
    lda ih_i
    sta WRDIVL              ; step = x / 6
    stz WRDIVH
    lda #6
    sta WRDIVB
    jsr ih_divwait
    lda RDDIVL
    rep #$30
.ACCU 16
    and #$00FF
    clc
    adc ih_src
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_WAVES,x
    and #$0F
    asl
    sta ih_t
    lda #30
    sec
    sbc ih_t
    sta ih_ya
    inc a
    sta ih_yb
    lda ih_i
    jsr ih_setx
    jsr ih_vspan
    inc ih_i
    lda ih_i
    cmp 1,s
    bne @col
    pla
    rts

ih_bank_info:
    lda #IH_X
    sta text_x
    lda #14
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    ldx #str_ih_steps
    jmp ih_puts

; --- envelope ------------------------------------------------------------------------
; step 0: clear, caption, and the curve's points
ih_env_begin:
    rep #$20
.ACCU 16
    lda #IH_WBYTES
    sta ih_base
    lda #IH_ABYTES
    jsr ih_clear
.ACCU 8
    lda #IH_X
    sta text_x
    lda #20
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    lda #24
    jsr ih_spaces
    lda ih_akey             ; type: SMP/KIT/WAV/NSE use the DSP ADSR
    cmp #$04
    bcc +
    lda #IH_X
    sta text_x
    ldx #str_ih_synth
    jsr ih_puts
    rts
+
    ; points: (0,23) (A,1) (A+D, SL) (191, end)
    lda ih_akey + 1
    and #$0F
    rep #$30
.ACCU 16
    and #$000F
    tax
    sep #$20
.ACCU 8
    lda.l ih_atab,x
    sta es0                 ; x1
    lda ih_akey + 1
    lsr
    lsr
    lsr
    lsr
    and #$07
    rep #$30
.ACCU 16
    and #$0007
    tax
    sep #$20
.ACCU 8
    lda.l ih_dtab,x
    clc
    adc es0
    sta es0 + 1             ; x2
    lda ih_akey + 2
    lsr
    lsr
    lsr
    lsr
    lsr
    rep #$30
.ACCU 16
    and #$0007
    tax
    sep #$20
.ACCU 8
    lda.l ih_sltab,x
    sta es1 + 1             ; y at the sustain level
    ; end level: (23 - y_sl) * (256 - drop) / 256, from the SR table
    lda ih_akey + 2
    and #$1F
    rep #$30
.ACCU 16
    and #$001F
    tax
    sep #$20
.ACCU 8
    lda.l ih_srtab,x
    beq @flat
    eor #$FF
    inc a                   ; 256 - drop (drop >= 1)
    sta WRMPYA
    lda #23
    sec
    sbc es1 + 1
    sta WRMPYB
    nop
    nop
    nop
    nop
    lda RDMPYH              ; level * (256-drop) / 256
    sta ih_t
    lda #23
    sec
    sbc ih_t
    bra @have_end
@flat:
    lda es1 + 1
@have_end:
    sta ih_yend
    lda es0
    sta ih_px1
    lda es0 + 1
    sta ih_px2
    lda es1 + 1
    sta ih_ysl
    rts

; steps 1-4: (0,23)-(px1,1), (px1,1)-(px2,ysl), then the long sustain
; segment (px2,ysl)-(191,yend) in two halves so no step is heavy
ih_env_seg:
    lda ih_akey
    cmp #$04
    bcc +
    rts                     ; SLICE/KARP: no DSP envelope drawn
+
    lda ih_step
    cmp #2
    beq @two
    bcs @three
    stz es2
    lda #23
    sta es2 + 1
    lda ih_px1
    sta es3
    lda #1
    sta es3 + 1
    jmp ih_line
@two:
    lda ih_px1
    sta es2
    lda #1
    sta es2 + 1
    lda ih_px2
    sta es3
    lda ih_ysl
    sta es3 + 1
    jmp ih_line
@three:
    ; midpoint of the sustain segment
    lda ih_px2
    clc
    adc #191
    ror                     ; (px2 + 191) / 2, carry in
    sta es3
    lda ih_ysl
    clc
    adc ih_yend
    lsr
    sta es3 + 1
    lda ih_step
    cmp #4
    beq @four
    lda ih_px2
    sta es2
    lda ih_ysl
    sta es2 + 1
    jmp ih_line
@four:
    lda es3
    sta es2
    lda es3 + 1
    sta es2 + 1
    lda #191
    sta es3
    lda ih_yend
    sta es3 + 1
    jmp ih_line

; line (es2, es2+1) -> (es3, es3+1), x1 > x0. One divide per segment for
; the 8.8 slope, then each column draws the span from the previous
; column's y to its own, so steep parts stay joined.
ih_line:
    lda es3
    sec
    sbc es2
    bne +
    rts
+
    sta tmp0 + 1            ; dx
    stz tmp0                ; i
    lda es2 + 1
    sta ih_t                ; previous y
    ; slope = |dy| * 256 / dx
    lda es3 + 1
    sec
    sbc es2 + 1
    bcs +
    eor #$FF
    inc a
+
    stz WRDIVL
    sta WRDIVH
    lda tmp0 + 1
    sta WRDIVB
    jsr ih_divwait
    ldx RDDIVL
    stx ih_slope
    rep #$20
.ACCU 16
    stz ih_acc
    sep #$20
.ACCU 8
@col:
    lda es3 + 1
    cmp es2 + 1             ; C set: falling or flat (y grows)
    lda ih_acc + 1
    bcs @down
    eor #$FF
    inc a                   ; rising: y0 - q
@down:
    clc
    adc es2 + 1             ; y
    cmp ih_t
    bcs +
    sta ih_ya
    lda ih_t
    sta ih_yb
    lda ih_ya
    bra @set
+
    sta ih_yb
    lda ih_t
    sta ih_ya
    lda ih_yb
@set:
    sta ih_t                ; this column's y becomes the previous
    lda es2
    clc
    adc tmp0
    jsr ih_setx
    jsr ih_vspan
    rep #$20
.ACCU 16
    lda ih_acc
    clc
    adc ih_slope
    sta ih_acc
    sep #$20
.ACCU 8
    lda tmp0
    cmp tmp0 + 1
    beq @done
    inc tmp0
    bra @col
@done:
    rts

; A16 = value 0-999 printed without leading zeros (A8 on return)
ih_dec:
.ACCU 16
    sta WRDIVL
    sep #$20
.ACCU 8
    lda #10
    sta WRDIVB
    jsr ih_divwait
    lda RDMPYL              ; ones
    pha
    ldx RDDIVL
    stx WRDIVL
    lda #10
    sta WRDIVB
    jsr ih_divwait
    lda RDMPYL              ; tens
    pha
    lda RDDIVL              ; hundreds
    beq @no_h
    clc
    adc #'0' - 32
    jsl text_puttile_l
    pla
    bra @tens
@no_h:
    pla
    beq @ones               ; no hundreds and no tens
@tens:
    clc
    adc #'0' - 32
    jsl text_puttile_l
@ones:
    pla
    clc
    adc #'0' - 32
    jsl text_puttile_l
    rts

; A16 = tenths -> "N.N" (A8 on return)
ih_dec_tenths:
.ACCU 16
    sta WRDIVL
    sep #$20
.ACCU 8
    lda #10
    sta WRDIVB
    jsr ih_divwait
    lda RDMPYL
    pha
    rep #$20
.ACCU 16
    lda RDDIVL
    jsr ih_dec
.ACCU 8
    lda #'.' - 32
    jsl text_puttile_l
    pla
    clc
    adc #'0' - 32
    jsl text_puttile_l
    rts

; envelope geometry (tools-free: computed once, see the UI rewrite report)
; attack/decay widths in pixels on a log scale of the DSP rate times;
; sustain-level rows; sustain-rate drop (of 256) over the right segment
; standing for ~1.5 s
ih_atab:  .DB 60, 57, 53, 50, 47, 43, 41, 37, 34, 31, 28, 24, 22, 19, 16, 2
ih_dtab:  .DB 40, 37, 35, 32, 30, 27, 25, 21
ih_sltab: .DB 20, 17, 15, 12, 9, 7, 4, 1
ih_srtab: .DB 0, 10, 14, 16, 20, 27, 32, 41, 54, 65, 82, 110, 132, 160, 213, 255
          .DB 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255

str_ih_wave:    .DB "WAVE", 0
str_ih_env:     .DB "ENVELOPE", 0
str_ih_nosmp:   .DB "NO SAMPLE", 0
str_ih_kb:      .DB "KB  ", 0
str_ih_oneshot: .DB "ONE-SHOT", 0
str_ih_loop:    .DB "LOOPS AT ", 0
str_ih_bank:    .DB "BANK ", 0
str_ih_steps:   .DB "32 STEPS", 0
str_ih_synth:   .DB "SYNTH ENVELOPE", 0

ih_peaks:
    .INCBIN "peaks.bin"

.ENDS
