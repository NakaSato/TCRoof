// Scripted walkthrough of mount-layout.html (frames of img/mount_demo.mp4). Usage: node mount-demo.js [outDir]
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const OUT = process.argv[2] || 'mount-frames'; fs.mkdirSync(OUT, { recursive: true });
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1366, height: 1300 } });
  await p.setContent('<!doctype html><meta charset=utf-8><style>[hidden]{display:none!important}body{margin:0}</style>' +
    fs.readFileSync(path.join(__dirname, 'mount-layout.html'), 'utf8'));
  await p.waitForTimeout(800);
  const frames = []; let n = 0;
  const shot = async (cap, hold = 1) => { await p.waitForTimeout(150); const f = `${OUT}/f${String(n++).padStart(3, '0')}.png`;
    await p.screenshot({ path: f, clip: { x: 0, y: 130, width: 1366, height: 1150 } }); frames.push({ f, cap, hold }); };
  const clickSel = async sel => { const q = await p.$eval(sel, e => { const r = e.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; }); await p.mouse.click(q[0], q[1]); };
  const slide = async (id, v) => p.evaluate(([id, v]) => { const e = document.getElementById(id); e.dispatchEvent(new PointerEvent('pointerdown')); e.value = v; e.dispatchEvent(new Event('input')); }, [id, v]);
  await shot('เปิดแท็บโครงสร้าง: ระบบวางโต๊ะแผง เสา ราง และฐานให้เองจากแปลนฝาถัง', 3);
  // vents: one that fits under, one that does not
  const vents = await p.$$eval('[data-vent]', es => es.map(e => e.dataset.vent));
  let okShown = false, badShown = false;
  for (const v of vents) {
    await clickSel(`[data-vent="${v}"]`); const t = await p.textContent('#info');
    if (!okShown && t.includes('วางแผงคร่อมได้')) { okShown = true; await shot('แตะช่องระบาย: ใต้แผงสูงพอ จึงวางแผงคร่อมได้', 3); }
    else if (!badShown && t.includes('ต่ำไป')) { badShown = true; await shot('ช่องระบายอีกจุด: ใต้แผงต่ำไป ระบบจึงเว้นแผงเหนือช่องนี้', 3); }
    if (okShown && badShown) break;
  }
  const bad = await p.$$eval('[data-post]', es => { for (const e of es) { const c = e.getAttribute('cx'); } return es.map(e => e.dataset.post); });
  // red post: find via notes text, click posts until the info says it collides
  for (const d of bad) { await clickSel(`[data-post="${d}"]`); if ((await p.textContent('#info')).includes('ชนช่องเปิด')) { await shot('แตะเสาสีแดง: ชนช่องเปิด เลื่อนหลบไม่ได้ ระบบบอกทางแก้', 3); break; } }
  for (const v of [0.2, 0.4, 0.6, 0.8, 1.0]) { await slide('off', v); await shot('เลื่อนแนวแถว: จำนวนแผงและวัสดุเปลี่ยนทันที (เลขเขียว/แดงคือส่วนต่าง)', 1); }
  await p.click('#best'); await shot('กด “หาผังที่ได้แผงมากที่สุด”: ลองทุกแนวแล้วเลือกแบบที่ได้แผงมากสุด', 4);
  // select a table in row 3 then its section
  const m = await p.$$eval('.hit.m', es => es.map(e => [e.dataset.row, e.dataset.col]));
  const pick = m.find(([r, c]) => r === '2' && +c > 10) || m[40];
  await clickSel(`.hit.m[data-row="${pick[0]}"][data-col="${pick[1]}"]`); await shot('แตะโต๊ะแผง: ดูจำนวนแผง ความยาว เสา และเสาที่ถูกเลื่อนหลบ', 3);
  await p.click('#toSection'); await shot('ดูรูปตัดแถวนี้: เสาหน้า–หลัง มุมเอียง และช่องระบายที่อยู่ใต้แผง', 3);
  await p.click('[data-view="plan"]');
  await p.click('[data-mode="remove"]'); await shot('โหมด “เอาแผงออก / ใส่คืน”: ใช้เว้นทางเดิน', 2);
  for (const r of ['0', '1', '2', '3']) { await clickSel(`.hit.m[data-row="${r}"][data-col="16"]`); await shot('แตะแผงเพื่อเอาออก: เว้นทางเดินกลางถัง ตัวเลขลดตาม', 1); }
  await p.click('#undo'); await shot('ย้อนกลับได้ทุกขั้น', 2);
  await p.click('[data-mode="inspect"]');
  await p.fill('#gap', '3.2'); await p.press('#gap', 'Tab'); await shot('เปลี่ยนมาตรฐาน: ระหว่างแถว 3.20 ม. แถวลดลง จัดผังใหม่ทันที', 3);
  await p.click('#resetStd'); await p.selectOption('#north', 'right'); await shot('ทิศเหนืออยู่ด้านขวาของแปลน: หมุนแปลนแล้วจัดแถวใหม่ให้แผงหันทิศใต้', 3);
  await p.selectOption('#north', 'top'); await p.click('[data-preset="t64"]'); await p.click('#best'); await shot('ถัง 64 × 40: วางอัตโนมัติและหาผังที่ได้แผงมากที่สุด', 4);
  fs.writeFileSync(OUT + '/frames.json', JSON.stringify(frames)); await b.close();
})();
