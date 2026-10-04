// Scripted walkthrough of roof-layout.html (frames of img/roof_demo.mp4). Usage: node roof-demo.js [outDir]
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const OUT = process.argv[2] || 'roof-frames'; fs.mkdirSync(OUT, { recursive: true });
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1366, height: 1300 } });
  await p.setContent('<!doctype html><meta charset=utf-8><style>[hidden]{display:none!important}body{margin:0}</style>' +
    fs.readFileSync(path.join(__dirname, 'roof-layout.html'), 'utf8'));
  await p.waitForTimeout(800);
  const frames = []; let n = 0;
  const shot = async (cap, hold = 1) => { await p.waitForTimeout(150); const f = `${OUT}/f${String(n++).padStart(3, '0')}.png`;
    await p.screenshot({ path: f, clip: { x: 0, y: 130, width: 1366, height: 1000 } }); frames.push({ f, cap, hold }); };
  const clickSel = async sel => { const q = await p.$eval(sel, e => { const r = e.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; }); await p.mouse.click(q[0], q[1]); };
  const setNum = async (id, v) => { await p.fill('#' + id, String(v)); await p.press('#' + id, 'Tab'); await p.waitForTimeout(100); };
  const slide = async (id, v) => p.evaluate(([id, v]) => { const e = document.getElementById(id); e.dispatchEvent(new PointerEvent('pointerdown')); e.value = v; e.dispatchEvent(new Event('input')); }, [id, v]);
  const cuts = async () => +(await p.$$eval('.stat', es => es.find(e => e.textContent.includes('ช่องที่ตัดหลบขา')).querySelector('b').firstChild.textContent));
  await shot('เปิดแท็บแผงบนหลังคา: ระบบวางแผง ราง และ L-foot ให้เองจากแปลนหลังคา C1', 3);
  const obs = await p.$$eval('[data-obs]', es => es.map(e => e.dataset.obs));
  await clickSel(`[data-obs="${obs[obs.length - 3]}"]`); await shot('แตะปล่อง (สูง 2.50 ม.): เว้นแผงออกจากเงาช่วง 09:00–15:00 ทั้งปี (พื้นสีส้ม)', 3);
  await clickSel(`[data-obs="${obs[0]}"]`); await shot('แตะแผ่นโปร่งแสง: แผงห่าง 0.10 ม. แต่ L-foot ต้องห่าง 0.50 ม.', 3);
  const m = await p.$$eval('.hit.m', es => es.map(e => [e.dataset.face, e.dataset.row, e.dataset.col]));
  const pick = m.find(([f, r, c]) => f === 'S' && r === '0' && +c === 12);
  await clickSel(`.hit.m[data-face="S"][data-row="0"][data-col="${pick[2]}"]`); await shot('แตะแผง: ทั้งชุดแผงต่อเนื่องเป็นสีส้ม รางตกแปทั้ง 2 เส้น ขาไม่ชนสิ่งกีดขวาง', 3);
  const feet = await p.$$eval('[data-foot]', es => es.map(e => e.dataset.foot));
  await clickSel(`[data-foot="${feet.find(k => k.startsWith('S:0:'))}"]`); await shot('แตะ L-foot: อยู่บนแปไหน และห่างสิ่งกีดขวางใกล้สุดเท่าไร', 2);
  await clickSel(`.hit.m[data-face="S"][data-row="0"][data-col="${pick[2]}"]`); await p.click('#toSection');
  await shot('ดูรูปตัดแถวนี้: รางวางตรงแป ระยะจับแผงจากปลายอยู่ในช่วงที่ผู้ผลิตกำหนด', 4);
  await p.click('[data-view="plan"]');
  await setNum('purlin', 1.5); await shot('แก้ระยะแป 1.20 → 1.50 ม.: รางตกแปไม่ได้ทุกแถว จำนวนแถวลดลงทันที', 3);
  await setNum('purlin', 1.0); await shot('ระยะแป 1.00 ม.: แถวจัดใหม่ให้รางตกแปทั้งคู่', 2);
  await setNum('purlin', 1.2);
  await p.click('[data-mount="rib"]'); await shot('เปลี่ยนเป็นจับสันลอน: ไม่ต้องตรงแป แถวชิดกันได้ ใช้เทียบกับยึดเข้าแป', 3);
  await p.click('[data-mount="purlin"]');
  // find a column offset that forces a cut, to show the red outline
  let found = false;
  for (let k = 0; k <= 23 && !found; k++) { await slide('col', (k * 0.05).toFixed(2)); if (await cuts() > 0) found = true; }
  if (found) {
    const cut = await p.$$eval('.mod.cut', es => es.length);
    await shot('เลื่อนแนวแผง: ถ้า L-foot หลบสิ่งกีดขวางไม่ได้ ระบบตัดแผงช่องนั้นออก (กรอบแดง)', 3);
    const slots = await p.$$eval('.hit.m', es => es.map(e => [e.dataset.face, e.dataset.row, e.dataset.col]));
    for (const [f, r, c] of slots) { await clickSel(`.hit.m[data-face="${f}"][data-row="${r}"][data-col="${c}"]`);
      if ((await p.textContent('#info')).includes('ตัดแผงเพื่อไม่ให้ขา')) { await shot('แตะกรอบแดง: ตัดแผงเพื่อไม่ให้ขาโครงสร้างชนสิ่งกีดขวาง', 3); break; } }
  }
  await p.click('#best'); await shot('กด “หาผังที่ได้แผงมากที่สุด”: ลองทุกแนวแผงและแนวแถว ทุกด้านหลังคา', 3);
  await p.click('[data-mode="inspect"]'); await p.click('[data-use="N"]'); await shot('ปิดด้านเหนือ: แผงด้านนั้นเป็นเส้นประแดง ตัวเลขลดตาม', 2);
  await p.click('[data-use="N"]');
  await p.click('[data-mode="remove"]');
  for (const r of ['0', '1', '2', '3']) { await clickSel(`.hit.m[data-face="S"][data-row="${r}"][data-col="14"]`); await shot('โหมดเอาแผงออก: เว้นทางเดินขึ้นหลังคา', 1); }
  await p.click('#undo'); await shot('ย้อนกลับได้ทุกขั้น', 2);
  await p.click('[data-mode="inspect"]');
  await p.click('[data-preset="hip"]'); await shot('หลังคาปั้นหยา: 4 ด้าน แต่ละด้านคิดทิศและพลังงานแยกกัน ร่นตามแนวตะเข้', 4);
  await p.click('[data-preset="shed"]'); await shot('หลังคาเพิงหมาแหงน: ระยะแป 1.10 ม. ทำให้แถวจับคู่กันเป็นช่วง', 4);
  fs.writeFileSync(OUT + '/frames.json', JSON.stringify(frames)); await b.close();
})();
