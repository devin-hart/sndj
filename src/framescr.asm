; framescr.asm — the FRAME editor: every track's phrase at one song row
; and chain step, side by side (FamiTracker-style chord writing).
; UI REWRITE (branch ui-rewrite). Bank 7.
;
; Position = (fr_row, fr_step): the song row and chain step. Track t's
; column is the phrase its chain holds at that step (fr_ph[t], $FF =
; nothing plays there). The groove is global, so row r of every column
; plays at the same moment unless a track HOPs.
;
; Editing is the PHRASE screen's own code: each frame ed_phrase/cur_y/
; ed_col point at the cursor track's cell and phrase_update runs with its
; drawing suppressed (phrase_draw returns early on SCREEN_FRAME). The
; d-pad is taken here first (unless B is held for a nudge, or a block is
; being selected), so the cursor walks across tracks and through steps.
;
; Hi-res (OPTIONS HI-RES ON): 8 tracks x 7 columns, colour.
; Classic: 3 tracks x 8 columns, side-scrolling with the cursor.
;
; X on PHRASE opens FRAME at that phrase; X on FRAME returns to PHRASE.

.BANK 7 SLOT 0
.SECTION "Frame editor" FREE

.ACCU 8
.INDEX 16

.DEFINE FR_Y0    5           ; first grid row
.DEFINE FR_X0    3           ; first track column (x0-1 label, x2 playhead)

; --- X on PHRASE: open FRAME on the phrase being edited ------------------------
frame_enter:
    lda song_cy
    sta fr_row
    lda chain_cy
    sta fr_step
    lda song_cx
    and #$07
    sta fr_trk
    stz fr_left
    lda cur_y
    pha
    lda ed_col
    pha
    jsl text_clear_l        ; also leaves hi-res
    pla
    sta ed_col
    pla
    sta cur_y
    lda #SCREEN_FRAME
    sta ui_mode
    stz blk_mode
    stz tap_live
    stz b_down
    lda opt_hires
    beq @classic
    jsl hr_enter
    lda #7
    sta fr_w
    lda #8
    sta fr_vis
    bra @geo
@classic:
    lda #8
    sta fr_w
    lda #3
    sta fr_vis
@geo:
    jsr fr_scroll
    lda #$FF
    sta fr_head
    lda #$01
    sta fr_full
    ; static text
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    sta text_attr
    sep #$20
.ACCU 8
    stz text_x
    lda #1
    sta text_y
    ldx #str_fr_title
    jsr fr_puts
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    sta text_attr
    sep #$20
.ACCU 8
    stz text_x
    lda #24
    sta text_y
    ldx #str_fr_hint
    jsr fr_puts
    rtl

; X = string in this bank
fr_puts:
    phb
    phk
    plb
    jsl text_puts_l
    plb
    rts

; keep the cursor track inside the visible window
fr_scroll:
    lda fr_trk
    cmp fr_left
    bcs +
    sta fr_left
    bra @done
+
    lda fr_left
    clc
    adc fr_vis
    dec a                   ; last visible track
    cmp fr_trk
    bcs @done
    lda fr_trk
    sec
    sbc fr_vis
    inc a
    sta fr_left
@done:
    rts

; --- per frame ------------------------------------------------------------------
frame_update:
    ; X: back to PHRASE (cursor row/column kept)
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_X
    sep #$20
.ACCU 8
    beq @no_x
    lda cur_y
    pha
    lda ed_col
    pha
    lda ed_phrase
    cmp #$FF
    beq @stay               ; nothing to edit at this step
    jsl phrase_init_l
    pla
    sta ed_col
    pla
    sta cur_y
    rtl
@stay:
    pla
    pla
@no_x:
    ; did anything arrive this frame? (edits only happen on input)
    rep #$20
.ACCU 16
    lda pad_pressed
    ora pad_event
    sta fr_input
    sep #$20
.ACCU 8
    lda fr_trk
    sta fr_oldtrk
    lda a_down
    bne @nav_done           ; A held: map navigation owns the d-pad
    lda blk_mode
    bne @nav_done           ; block select stretches inside the phrase
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_B
    sep #$20
.ACCU 8
    bne @nav_done           ; B held + d-pad = nudge (phrase code)
    jsr fr_nav
@nav_done:
    ; Y + up/down belongs to FRAME (steps). With B held or a block active
    ; fr_nav is skipped, so drop them here too: PHRASE's own Y+UP/DOWN
    ; path would page its chain and paint its header over this screen.
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_Y
    beq +
    lda pad_event
    and #($FFFF - PAD_UP - PAD_DOWN)
    sta pad_event
+
    sep #$20
.ACCU 8
    jsr fr_context
    ; the PHRASE editor on the cursor cell (its drawing is suppressed)
    lda ed_phrase
    cmp #$FF
    beq @no_phrase
    jsl phrase_update_l
    bra @edited
@no_phrase:
    rep #$20
.ACCU 16
    lda pad_pressed
    and #PAD_START
    sep #$20
.ACCU 8
    beq @edited
    jsl engine_toggle_l
@edited:
    ; --- drawing ---
    jsr fr_context          ; an edit may have minted/cloned a phrase
    lda fr_full
    beq @partial
    stz fr_full
    jsr fr_draw_full
    bra @head
@partial:
    rep #$20
.ACCU 16
    lda fr_input
    sep #$20
.ACCU 8
    beq @head
    ; input: redraw the cursor column (and the previous one if the cursor
    ; changed tracks), plus any column showing the same phrase
    lda fr_oldtrk
    cmp fr_trk
    beq +
    jsr fr_draw_col
+
    lda fr_trk
    jsr fr_draw_col
    jsr fr_draw_shared
    jsr fr_draw_info
@head:
    jmp fr_draw_head

; d-pad: cursor across columns/tracks and down through chain steps
fr_nav:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DPAD
    sep #$20
.ACCU 8
    bne +
    rts
+
    ; Y held + up/down: a whole step at a time
    rep #$20
.ACCU 16
    lda pad_held
    and #PAD_Y
    sep #$20
.ACCU 8
    beq @left
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq +
    jsr fr_step_back
+
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @eat
    jsr fr_step_fwd
    bra @eat
@left:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_LEFT
    sep #$20
.ACCU 8
    beq @right
    lda ed_col
    beq +
    dec ed_col
    bra @right
+
    lda #3
    sta ed_col
    lda fr_trk
    dec a
    and #$07
    sta fr_trk
@right:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_RIGHT
    sep #$20
.ACCU 8
    beq @up
    lda ed_col
    cmp #3
    bcs +
    inc ed_col
    bra @up
+
    stz ed_col
    lda fr_trk
    inc a
    and #$07
    sta fr_trk
@up:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_UP
    sep #$20
.ACCU 8
    beq @down
    lda cur_y
    beq +
    dec cur_y
    bra @down
+
    jsr fr_step_back
    bcc @down
    lda #15
    sta cur_y
@down:
    rep #$20
.ACCU 16
    lda pad_event
    and #PAD_DOWN
    sep #$20
.ACCU 8
    beq @eat
    lda cur_y
    cmp #15
    bcs +
    inc cur_y
    bra @eat
+
    jsr fr_step_fwd
    bcc @eat
    stz cur_y
@eat:
    stz tap_live            ; moving ends a pending double-tap
    rep #$20
.ACCU 16
    lda pad_event
    and #$F0FF              ; drop the d-pad bits (PAD_DPAD = $0F00)
    sta pad_event
    sep #$20
.ACCU 8
    lda fr_left
    pha
    jsr fr_scroll
    pla
    cmp fr_left
    beq +
    lda #$01
    sta fr_full
+
    rts

; previous / next chain step (into the neighbouring song row at the ends);
; C set when the position moved
fr_step_back:
    lda fr_step
    beq +
    dec fr_step
    bra @moved
+
    lda fr_row
    bne +
    clc                     ; already at row 00 step 0
    rts
+
    dec fr_row
    lda #15
    sta fr_step
@moved:
    lda #$01
    sta fr_full
    sec
    rts

fr_step_fwd:
    lda fr_step
    cmp #15
    bcs +
    inc fr_step
    bra @moved
+
    lda fr_row
    cmp #127
    bcc +
    clc
    rts
+
    inc fr_row
    stz fr_step
@moved:
    lda #$01
    sta fr_full
    sec
    rts

; fr_ph[t] = phrase of track t at (fr_row, fr_step); full redraw when any
; changed. Also points the PHRASE/CHAIN/SONG context at the cursor cell
; (so A+left/right and X leave FRAME exactly where the cursor is).
fr_context:
    ldy #$0000
@trk:
    rep #$30
.ACCU 16
    tya
    xba
    lsr                     ; t*128
    sta tmp1
    lda fr_row
    and #$00FF
    clc
    adc tmp1
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_SONG,x
    cmp #$FF
    beq @none
    rep #$30
.ACCU 16
    and #$00FF
    asl
    asl
    asl
    asl
    asl                     ; chain*32
    sta tmp1
    lda fr_step
    and #$00FF
    asl
    clc
    adc tmp1
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_CHAINS,x
@none:
    cmp.w fr_ph,y
    beq +
    sta.w fr_ph,y
    lda #$01
    sta fr_full
+
    iny
    cpy #TRACKS
    bne @trk
    ; context for the cursor track
    lda fr_trk
    sta song_cx
    lda fr_row
    sta song_cy
    lda fr_step
    sta chain_cy
    rep #$30
.ACCU 16
    lda fr_trk
    and #$00FF
    tay
    xba
    lsr
    sta tmp1
    lda fr_row
    and #$00FF
    clc
    adc tmp1
    tax
    sep #$20
.ACCU 8
    lda.l $7E0000 + SB_SONG,x
    sta ed_chain
    lda.w fr_ph,y
    sta ed_phrase
    rts

; --- drawing --------------------------------------------------------------------
; A16 attr -> text_attr; the colour roles (palettes 5-7) exist only in
; hi-res, so classic draws them as plain text
fr_attr:
.ACCU 16
    bit ui_hires - 1        ; N = bit 7 of ui_hires (high byte of the word)
    bmi +
    cmp #ATTR_GREEN
    bcc +
    lda #ATTR_TEXT
+
    sta text_attr
    sep #$20
.ACCU 8
    rts

fr_draw_full:
    ; title line: ROW rr STEP s
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr fr_attr
.ACCU 8
    lda #7
    sta text_x
    lda #1
    sta text_y
    ldx #str_fr_row
    jsr fr_puts
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    jsr fr_attr
.ACCU 8
    lda fr_row
    jsl text_hex8_l
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr fr_attr
.ACCU 8
    ldx #str_fr_step
    jsr fr_puts
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    jsr fr_attr
.ACCU 8
    lda fr_step
    jsr fr_nibble
    ; scroll hints (classic): < and > when tracks are off screen
    lda opt_hires
    bne @labels
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    jsr fr_attr
.ACCU 8
    stz text_x
    lda #4
    sta text_y
    lda fr_left
    beq @no_lt
    lda #'<' - 32
    bra @lt
@no_lt:
    lda #' ' - 32
@lt:
    jsl text_puttile_l
    lda #FR_X0 + 3 * 8
    sta text_x
    lda fr_left
    clc
    adc #3
    cmp #TRACKS
    bcs @no_gt
    lda #'>' - 32
    bra @gt
@no_gt:
    lda #' ' - 32
@gt:
    jsl text_puttile_l
@labels:
    ; row labels (white on the beat)
    stz fr_r
@lab:
    lda fr_r
    clc
    adc #FR_Y0
    sta text_y
    stz text_x
    lda fr_r
    and #$03
    rep #$20
.ACCU 16
    beq @beat
    lda #ATTR_DIM
    bra @lset
@beat:
    lda #ATTR_HILITE
@lset:
    jsr fr_attr
.ACCU 8
    lda fr_r
    jsl text_hex8_l
    lda #' ' - 32           ; the gutter: the arrow is redrawn after
    jsl text_puttile_l
    inc fr_r
    lda fr_r
    cmp #16
    bne @lab
    ; every visible column
    lda fr_left
    sta fr_cnt
@col:
    lda fr_cnt
    jsr fr_draw_col
    inc fr_cnt
    lda fr_left
    clc
    adc fr_vis
    cmp fr_cnt
    bne @col
    lda #$FF
    sta fr_head             ; the playhead arrow was wiped: redraw it
    jmp fr_draw_info

; A = hex digit 0-15 drawn as one glyph
fr_nibble:
    and #$0F
    cmp #10
    bcc +
    adc #6
+
    adc #'0' - 32
    jsl text_puttile_l
    rts

; text_x for track A (A must be visible) -> fr_x
fr_colx:
    sec
    sbc fr_left
    sta tmp1                ; visible index
    asl
    asl
    asl                     ; *8
    pha
    lda fr_w
    cmp #8
    pla
    bcs +
    sec
    sbc tmp1                ; *7 in hi-res
    clc
    adc #FR_X0
    sta fr_x
    rts
+
    clc
    adc #FR_X0 + 1          ; classic: a gap column leads each track
    sta fr_x
    rts

; redraw track A's column (no-op when A is scrolled out of view)
fr_draw_col:
    sta fr_t
    cmp fr_left
    bcs +
    rts
+
    sec
    sbc fr_left
    cmp fr_vis
    bcc +
    rts
+
    lda fr_t
    jsr fr_colx
    ; header: track number + its phrase at this step
    lda fr_x
    sta text_x
    lda #4
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    jsr fr_attr
.ACCU 8
    lda fr_t
    inc a
    jsr fr_nibble
    inc text_x
    rep #$30
.ACCU 16
    lda fr_t
    and #$00FF
    tay
    sep #$20
.ACCU 8
    lda.w fr_ph,y
    cmp #$FF
    bne +
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr fr_attr
.ACCU 8
    lda #'-' - 32
    jsl text_puttile_l
    lda #'-' - 32
    jsl text_puttile_l
    bra @rows
+
    pha
    rep #$20
.ACCU 16
    lda #ATTR_CYAN
    jsr fr_attr
.ACCU 8
    pla
    jsl text_hex8_l
@rows:
    lda #3                  ; clear the rest of the header cell
    sta fr_cnt2
-
    lda #' ' - 32
    jsl text_puttile_l
    dec fr_cnt2
    bne -
    stz fr_r
@row:
    jsr fr_draw_cell
    inc fr_r
    lda fr_r
    cmp #16
    bne @row
    rts

; one cell: track fr_t (column fr_x), row fr_r
fr_draw_cell:
    lda fr_r
    clc
    adc #FR_Y0
    sta text_y
    lda fr_w
    cmp #8
    bne +
    ; classic: clear the leading gap column
    lda fr_x
    dec a
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    jsr fr_attr
.ACCU 8
    lda #' ' - 32
    jsl text_puttile_l
+
    lda fr_x
    sta text_x
    rep #$30
.ACCU 16
    lda fr_t
    and #$00FF
    tay
    sep #$20
.ACCU 8
    lda.w fr_ph,y
    cmp #$FF
    bne @have
    ; nothing plays here at this step: blank the cell
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    jsr fr_attr
.ACCU 8
    lda #7
    sta fr_cnt2
-
    lda #' ' - 32
    jsl text_puttile_l
    dec fr_cnt2
    bne -
    rts
@have:
    ; the row's 4 bytes -> str_buf+32..35
    rep #$30
.ACCU 16
    and #$00FF
    xba
    lsr
    lsr                     ; phrase*64
    sta tmp1
    lda fr_r
    and #$00FF
    asl
    asl
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
    ; NOTE
    stz tmp0
    lda fr_r
    sta tmp0 + 1
    jsr fr_cellattr
    bcs +                   ; cursor/block: keep
    lda str_buf + 32
    rep #$20
.ACCU 16
    beq @n_dim
    and #$00FF
    cmp #NOTE_OFF
    beq @n_txt
    lda #ATTR_CYAN
    bra @n_set
@n_dim:
    lda #ATTR_DIM
    bra @n_set
@n_txt:
    lda #ATTR_TEXT
@n_set:
    jsr fr_attr
.ACCU 8
+
    lda str_buf + 32
    jsl draw_note_l
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    jsr fr_attr
.ACCU 8
    lda #' ' - 32
    jsl text_puttile_l
    ; INSTR
    lda #1
    sta tmp0
    jsr fr_cellattr
    bcs +
    lda str_buf + 33
    cmp #INSTR_NONE
    rep #$20
.ACCU 16
    beq @i_dim
    lda #ATTR_TEXT
    bra @i_set
@i_dim:
    lda #ATTR_DIM
@i_set:
    jsr fr_attr
.ACCU 8
+
    lda str_buf + 33
    cmp #INSTR_NONE
    bne +
    lda #'-' - 32
    jsl text_puttile_l
    lda #'-' - 32
    jsl text_puttile_l
    bra @i_done
+
    jsl text_hex8_l
@i_done:
    ; CMD letter (cursor on CMD or VAL highlights it; VAL shows below)
    lda #2
    sta tmp0
    jsr fr_cellattr
    bcs @c_draw
    lda #3
    sta tmp0
    jsr fr_cellattr
    bcs @c_draw
    rep #$20
.ACCU 16
    lda #ATTR_PINK
    jsr fr_attr
.ACCU 8
@c_draw:
    lda str_buf + 34
    bne +
    lda #' ' - 32
    jsl text_puttile_l
    rts
+
    clc
    adc #'A' - 32 - 1
    jsl text_puttile_l
    rts

; tmp0 = column, tmp0+1 = row, track fr_t: C set (text_attr set) when the
; cell is under the cursor or in the block; C clear otherwise
fr_cellattr:
    lda fr_t
    cmp fr_trk
    bne @no
    jsl cell_attr_l
    rep #$20
.ACCU 16
    lda text_attr
    cmp #ATTR_ACCENT
    sep #$20
.ACCU 8
    bne @no
    sec
    rts
@no:
    clc
    rts

; other visible columns showing the cursor track's phrase (shared)
fr_draw_shared:
    lda #0
    sta fr_cnt
@t:
    lda fr_cnt
    cmp fr_trk
    beq @next
    rep #$30
.ACCU 16
    and #$00FF
    tax
    lda fr_trk
    and #$00FF
    tay
    sep #$20
.ACCU 8
    lda.w fr_ph,x
    cmp #$FF
    beq @next
    cmp.w fr_ph,y
    bne @next
    lda fr_cnt
    jsr fr_draw_col
@next:
    inc fr_cnt
    lda fr_cnt
    cmp #TRACKS
    bne @t
    rts

; the inspector line: the cursor cell in full, with the sample's name
fr_draw_info:
    stz text_x
    lda #22
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_HILITE
    jsr fr_attr
.ACCU 8
    lda #'T' - 32
    jsl text_puttile_l
    lda fr_trk
    inc a
    jsr fr_nibble
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr fr_attr
.ACCU 8
    ldx #str_fr_ph
    jsr fr_puts
    lda ed_phrase
    cmp #$FF
    bne +
    ldx #str_fr_empty
    jsr fr_puts
    jmp @clear_rest
+
    rep #$20
.ACCU 16
    lda #ATTR_CYAN
    jsr fr_attr
.ACCU 8
    lda ed_phrase
    jsl text_hex8_l
    lda #' ' - 32
    jsl text_puttile_l
    ; the cursor row's bytes
    rep #$30
.ACCU 16
    lda ed_phrase
    and #$00FF
    xba
    lsr
    lsr
    sta tmp1
    lda cur_y
    and #$00FF
    asl
    asl
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
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    jsr fr_attr
.ACCU 8
    lda str_buf + 32
    jsl draw_note_l
    lda #' ' - 32
    jsl text_puttile_l
    lda str_buf + 33
    cmp #INSTR_NONE
    bne +
    ldx #str_fr_noins
    jsr fr_puts
    bra @cmd
+
    jsl text_hex8_l
    lda #' ' - 32
    jsl text_puttile_l
    ; the instrument's sample name (SMP/SLICE), else its type
    rep #$30
.ACCU 16
    lda str_buf + 33
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
    beq @smp
    cmp #$04
    beq @smp
    ldx #str_fr_nosmp
    jsr fr_puts
    bra @cmd
@smp:
    lda.l $7E0000 + SB_INSTR + 1,x
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
    sta fr_cnt2
-
    lda.l POOL_TABLE,x
    cmp #'a'
    bcc +
    sbc #32                 ; fold lowercase
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
    dec fr_cnt2
    bne -
    lda #' ' - 32
    jsl text_puttile_l
@cmd:
    lda str_buf + 34
    bne @have_cmd
    ; No command: draw "--- " in ATTR_DIM
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr fr_attr
.ACCU 8
    ldx #str_fr_nocmd
    jsr fr_puts
    lda #' ' - 32
    jsl text_puttile_l
    bra @cmdhelp
@have_cmd:
    rep #$20
.ACCU 16
    lda #ATTR_PINK
    jsr fr_attr
.ACCU 8
    lda str_buf + 34
    clc
    adc #'A' - 32 - 1
    jsl text_puttile_l
    lda str_buf + 35
    jsl text_hex8_l
    lda #' ' - 32
    jsl text_puttile_l

@cmdhelp:
    ; Draw command help text after V34
    ; In hi-res: on row 22 after the space (fits in 64 columns)
    ; In classic: on row 23 (32 columns)
    lda ui_hires
    bne +
    ; Classic: move to row 23, x = 0
    lda #23
    sta text_y
    stz text_x
+
    rep #$20
.ACCU 16
    lda #ATTR_DIM
    jsr fr_attr
.ACCU 8

    lda str_buf + 34
    beq @clear_rest         ; empty command -> clear line
    cmp #27
    bcs @clear_rest         ; safety clamp

    rep #$30
.ACCU 16
    lda str_buf + 34
    and #$00FF
    asl                     ; cmd * 2
    tax
    lda.l cmdhelp_ptrs,x
    tax
    sep #$20
.ACCU 8
    jsr fr_puts

@clear_rest:
    ; Erase remainder of line with spaces in current ATTR_DIM
    lda ui_hires
    bne @hr_clear
    ; Classic: clear row 22 tail (if text_y == 22), or row 23 tail
    jsr fr_clear_line
    lda text_y
    cmp #22
    bne @done
    ; If we were on row 22 (e.g. empty phrase), also clear all of row 23
    lda #23
    sta text_y
    stz text_x
    jsr fr_clear_line
    bra @done

@hr_clear:
    jsr fr_clear_line

@done:
    rts

; Clears with spaces in current text_attr from text_x to end of line
fr_clear_line:
    lda ui_hires
    bne +
    lda #32
    bra ++
+
    lda #64
++
    sta fr_cnt2
-
    lda text_x
    cmp fr_cnt2
    bcs +
    lda #' ' - 32
    jsl text_puttile_l
    bra -
+
    rts

; the playhead arrow in the gutter: the row any track plays at this
; frame position (they move in lockstep under the global groove)
fr_draw_head:
    lda #$FF
    sta fr_cnt
    lda eng_playing
    beq @have
    ldx #$0000
@t:
    lda.w trk_phrase,x
    cmp #$FF
    beq @next
    lda.w trk_songrow,x
    cmp fr_row
    bne @next
    lda.w trk_cpos,x
    cmp fr_step
    bne @next
    lda.w trk_prow,x
    sta fr_cnt
    bra @have
@next:
    inx
    cpx #TRACKS
    bne @t
@have:
    lda fr_cnt
    cmp fr_head
    bne +
    rtl
+
    ; erase the old arrow, draw the new one
    lda #2
    sta text_x
    lda fr_head
    cmp #16
    bcs +
    clc
    adc #FR_Y0
    sta text_y
    rep #$20
.ACCU 16
    lda #ATTR_TEXT
    jsr fr_attr
.ACCU 8
    lda #' ' - 32
    jsl text_puttile_l
+
    lda fr_cnt
    sta fr_head
    cmp #16
    bcs +
    clc
    adc #FR_Y0
    sta text_y
    lda #2
    sta text_x
    rep #$20
.ACCU 16
    lda #ATTR_GREEN
    jsr fr_attr
.ACCU 8
    lda #GLYPH_ARROW_R
    jsl text_puttile_l
+
    rtl

str_fr_title: .DB "FRAME", 0
str_fr_row:   .DB "ROW ", 0
str_fr_step:  .DB " STEP ", 0
str_fr_hint:  .DB "X PHRASE  Y+UP/DN STEP", 0
str_fr_ph:    .DB " P", 0
str_fr_empty: .DB "-- NOTHING AT THIS STEP        ", 0
str_fr_noins: .DB "--          ", 0
str_fr_nosmp: .DB "         ", 0
str_fr_nocmd: .DB "---", 0

.INCLUDE "cmdhelp.inc"

.ENDS
