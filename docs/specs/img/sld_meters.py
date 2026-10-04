"""MDB incomer metering (exec'd by sld.py and sld_form.py): a tap above the main MCCB to pilot lamps R Y B and
VS → V 0-500V. Fuses and the DPM (with its CT) are off by default — the team asked to leave them out."""


def fuse(sk, x, y, label="FUSE X 3"):
    sk.rect(x, y - 5, 40, 10, DARK, "white", 0.9); sk.line((x + 6, y + 3), (x + 34, y - 3), 0.8, DARK)
    sk.text(label, (x + 20, y - 13), 8.5, False, DARK, "center")


def lamp(sk, x, y, letter):
    sk.circle((x, y), 8, DARK, "white", 0.9); sk.text(letter, (x, y), 7.5, False, DARK, "center")
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        sk.line((x + dx * 7, y + dy * 7), (x + dx * 11, y + dy * 11), 0.7, DARK)


def incomer_meters(sk, x, y1, y2, ct_y, lamps=True, dpm=False, fuses=False):
    """Two taps off the incoming line above the main breaker: y1 lamps + voltmeter, y2 DPM. CT at ct_y feeds the DPM."""
    if lamps:
        sk.circle((x, y1), 2.4, DARK, DARK)
        if fuses: sk.line((x, y1), (x + 70, y1), 0.9, DARK); fuse(sk, x + 70, y1); sk.line((x + 110, y1), (x + 250, y1), 0.9, DARK)
        else: sk.line((x, y1), (x + 250, y1), 0.9, DARK)
        n = x + 180; sk.circle((n, y1), 2.4, DARK, DARK)
        sk.line((n, y1), (n, y1 - 26), 0.9, DARK); sk.line((n, y1 - 26), (n + 150, y1 - 26), 0.9, DARK)
        for k, c in enumerate("RYB"): lamp(sk, n + 40 + 50 * k, y1 - 26, c)
        sk.circle((x + 260, y1), 10, DARK, "white", 0.9); sk.text("VS", (x + 260, y1), 7, False, DARK, "center")
        sk.line((x + 270, y1), (x + 290, y1), 0.9, DARK)
        sk.rect(x + 290, y1 - 9, 28, 18, DARK, "white", 0.9); sk.text("V", (x + 304, y1), 8, False, DARK, "center")
        sk.text("0-500V", (x + 304, y1 + 18), 8, False, DARK, "center")
    if dpm:
        sk.circle((x, y2), 2.4, DARK, DARK); sk.line((x, y2), (x + 70, y2), 0.9, DARK)
        fuse(sk, x + 70, y2); sk.line((x + 110, y2), (x + 180, y2), 0.9, DARK)
        sk.line((x + 180, y2), (x + 180, y2 + 14), 0.9, DARK)
        sk.rect(x + 150, y2 + 14, 60, 32, DARK, "white", 0.9); sk.text("DPM", (x + 180, y2 + 30), 8.5, False, DARK, "center")
        sk.line((x + 180, y2 + 46), (x + 180, ct_y), 0.9, DARK); sk.line((x + 180, ct_y), (x + 10, ct_y), 0.9, DARK)


def mccb_label(sk, x, y, at_, af_, c=DARK):
    sk.text("MCCB,3P", (x, y - 16), 8.5, False, c)
    sk.text(f"{at_}AT", (x, y - 3), 8.5, False, c); sk.line((x - 1, y + 4), (x + 34, y + 4), 0.6, c)
    sk.text(f"{af_}AF", (x, y + 12), 8.5, False, c)
