// Scripted walkthrough of tank-layout.html (the frames of img/tank_demo.mp4). Usage: node tank-demo.js [outDir]
const { chromium } = require('playwright');
const fs = require('fs');
const OUT = process.argv[2] || 'demo-frames'; fs.mkdirSync(OUT, { recursive: true });
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1366, height: 1320 }, deviceScaleFactor: 1 });
  const html = fs.readFileSync(require('path').join(__dirname, 'tank-layout.html'), 'utf8');
  await p.setContent('<!doctype html><meta charset=utf-8><style>[hidden]{display:none!important}body{margin:0}</style>' + html); await p.waitForTimeout(800);
  const frames = []; let n = 0;
  const shot = async (cap, hold = 1) => { await p.waitForTimeout(120);
    const f = `${OUT}/f${String(n++).padStart(3,'0')}.png`;
    const box = await p.$eval('.board', e => { const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: Math.min(r.height, 900) }; });
    await p.screenshot({ path: f, clip: { x: 0, y: 140, width: 1366, height: 1060 } }); frames.push({ f, cap, hold }); };
  const cell = async (r, c) => p.$eval(`.d-cellhit[data-r="${r}"][data-c="${c}"]`, e => { const q = e.getBoundingClientRect(); return { x: q.x, y: q.y, w: q.width, h: q.height }; });
  // 1. start blank, type sizes
  await p.click('[data-preset="blank"]'); await shot('เริ่มจากว่าง: ยังไม่มีขนาด ระบบบอกว่าต้องกรอกอะไร', 2);
  await p.fill('#bx', '10@4'); await shot('กรอกช่วงเสาแนวยาว 10@4 (= 4 ม. สิบช่วง)', 1);
  await p.fill('#by', '10@4'); await p.fill('#height', '4.5'); await shot('กรอกแนวกว้าง 10@4 และความสูง 4.5 ม.: ผังวาดทันที พื้นที่ติดแผงเป็นสีเขียว', 3);
  // 2. vents
  for (const [r, c] of [[0,0],[0,4],[0,5],[0,9],[9,0],[9,9]]) { const q = await cell(r, c); await p.mouse.click(q.x + q.w/2, q.y + q.h/2); await shot('โหมด “ช่องระบาย”: แตะช่องเพื่อวางช่องระบายอากาศ พื้นที่ติดแผงลดลงตาม', 1); }
  await p.click('[data-vs="cross"]'); await shot('เปลี่ยนสัญลักษณ์เป็นกากบาทตามของจริงหน้างาน', 2);
  // 3. wall mode: add hatch on top wall at 10.2 m
  await p.click('button[data-mode="wall"]'); await shot('โหมด “ที่ผนัง”: แตะริมผนังเพื่อเพิ่มช่องเปิดตรงจุดนั้น', 2);
  const a = await cell(0, 0), ppm = a.w / 4;
  await p.mouse.click(a.x + 10.2 * ppm, a.y + 3); await shot('เลือกชนิด: ช่องลงถัง / บันได / ท่อ (ระยะตามผนังคิดให้เอง)', 3);
  await p.click('#menu button:has-text("ช่องลงถัง")'); await shot('ได้ช่องลงถัง แก้ระยะเป็นตัวเลขได้ที่แถบด้านบน', 2);
  // 4. drag along the wall
  const hb = await p.$eval('.d-open.sel', e => { const q = e.getBoundingClientRect(); return { x: q.x + q.width/2, y: q.y + q.height/2 }; });
  await p.mouse.move(hb.x, hb.y); await p.mouse.down();
  for (let i = 1; i <= 6; i++) { await p.mouse.move(hb.x + i * 0.8 * ppm, hb.y); await shot('โหมด “เลือก”: ลากไปตามผนัง ระยะอัปเดตทีละ 0.05 ม.', 1); }
  await p.mouse.up(); await shot('ปล่อยนิ้ว: ระยะใหม่บันทึกแล้ว', 2);
  // 5. undo
  await p.click('#undo'); await shot('ย้อนกลับ (↶) ได้ทุกขั้น', 2);
  // 6. add ladder on the left wall
  await p.click('button[data-mode="wall"]');
  await p.mouse.click(a.x + 3, a.y + 6.4 * ppm); await p.click('#menu button:has-text("บันไดขึ้นถัง")'); await shot('เพิ่มบันไดขึ้นถังที่ผนังซ้าย แยกจากช่องลงถัง', 2);
  // 7. section
  await p.fill('#above', '1.5'); await p.click('[data-view="section"]'); await shot('รูปตัด 1–1 และ 2–2: ส่วนพ้นดิน 1.5 ม. วาดระดับดินและดินกลบให้', 3);
  await p.click('[data-view="plan"]');
  // 8. full sheet
  await p.click('[data-preset="t40"]'); await shot('ตัวอย่างแบบ กปภ. 40 × 40 ครบทุกช่อง: ใช้ได้ประมาณ 1,367 ม² (≈ 228 kWp)', 4);
  fs.writeFileSync(OUT + '/frames.json', JSON.stringify(frames));
  await b.close();
})();
