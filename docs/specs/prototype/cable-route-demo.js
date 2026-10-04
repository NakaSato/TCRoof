// Scripted walkthrough of cable-route.html (frames of img/cable_demo.mp4). Usage: node cable-route-demo.js [outDir]
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const OUT = process.argv[2] || 'cable-frames'; fs.mkdirSync(OUT, { recursive: true });
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1366, height: 1300 } });
  await p.setContent('<!doctype html><meta charset=utf-8><style>[hidden]{display:none!important}body{margin:0}</style>' +
    fs.readFileSync(path.join(__dirname, 'cable-route.html'), 'utf8'));
  await p.waitForTimeout(800);
  const frames = []; let n = 0;
  const shot = async (cap, hold = 1) => { await p.waitForTimeout(150); const f = `${OUT}/f${String(n++).padStart(3, '0')}.png`;
    await p.screenshot({ path: f, clip: { x: 0, y: 130, width: 1366, height: 1040 } }); frames.push({ f, cap, hold }); };
  // site metres → screen point (picture is 640 px = 182.74 m wide, drawn 1100 px wide in the svg)
  const at = async (xm, ym) => p.evaluate(([xm, ym]) => { const s = document.getElementById('svg'), r = s.getBoundingClientRect(), vb = s.viewBox.baseVal, px = xm / (182.74 / 640) * 1100 / 640, py = ym / (182.74 / 640) * 1100 / 640;
    return [r.left + px / vb.width * r.width, r.top + py / vb.height * r.height]; }, [xm, ym]);
  const click = async (xm, ym) => { const [x, y] = await at(xm, ym); await p.mouse.move(x, y); await p.mouse.click(x, y); };
  const move = async (xm, ym) => { const [x, y] = await at(xm, ym); await p.mouse.move(x, y, { steps: 4 }); };
  const clickSel = async sel => { const q = await p.$eval(sel, e => { const r = e.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; }); await p.mouse.click(q[0], q[1]); };
  const change = async (sel, v) => { await p.selectOption(sel, String(v)); await p.waitForTimeout(100); };
  const fill = async (sel, v) => { await p.fill(sel, String(v)); await p.press(sel, 'Tab'); await p.waitForTimeout(100); };

  await shot('ภาพสถานที่ติดตั้งที่มีอยู่แล้ว: สัญลักษณ์ PV, INVERTER, MDB และเส้น DC กับสายสื่อสารที่ลากไว้', 3);
  await clickSel('[data-route="r1"][data-seg="1"]'); await shot('แตะเส้น DC: ระยะตามแนว ความยาวต่อสตริง สายรวม 20 สตริง × 2 และแรงดันตก', 3);
  await clickSel('[data-tool="route"]'); await clickSel('[data-kind="ac"]'); await change('#method', 'ug');
  await click(149, 64); await move(120, 63); await shot('ลากเส้น AC: แตะที่ INVERTER เส้นดูดติดสัญลักษณ์ ระยะขึ้นตามเมาส์', 2);
  await click(97, 62); await move(75, 62); await shot('แตะทีละมุมตามแนวที่จะขุดร่อง', 1);
  await click(60, 62); await change('#method', 'wall'); await move(52, 72); await shot('ช่วงสุดท้ายเข้าห้อง MDB เปลี่ยนเป็นท่อเกาะผนัง', 2);
  await click(50, 75); await shot('แตะ MDB เพื่อจบเส้น: นับจุดข้ามถนนและจุดทะลุผนังให้เอง', 3);
  await shot('แรงดันตกเกิน 2% ที่สาย 150 มม² ระบบแนะนำขนาดที่ผ่าน', 2);
  await change('#rSize', 185); await shot('เปลี่ยนเป็น 185 มม²: แรงดันตกผ่านเกณฑ์', 3);
  await clickSel('[data-cross^="r3:"]'); await shot('แตะจุดข้ามถนน: ร้อยท่อปลอกเหล็กตามความกว้างถนนและมุมที่ข้าม', 3);
  await clickSel('[data-route="r3"][data-seg="0"]'); await change('#segM', 'rack'); await shot('เปลี่ยนช่วงแรกเป็น Pipe Rack: ร่องฝังดินลด ข้ามถนนต้องตรวจความสูง', 3);
  await clickSel('#undo'); await clickSel('[data-route="r3"][data-seg="0"]');
  await click(50, 75); await p.waitForTimeout(150);   // select the MDB first so the info line (and the drawing's position) stays put while dragging
  const [mx, my] = await at(50, 75); await p.mouse.move(mx, my); await p.mouse.down(); await p.waitForTimeout(150);
  const [nx, ny] = await at(38, 72); await p.mouse.move(nx, ny, { steps: 6 }); await p.mouse.up();
  await shot('ลากย้าย MDB: เส้นที่ต่ออยู่ตามไป ความยาวและแรงดันตกคิดใหม่ทันที', 3);
  await clickSel('[data-tool="building"]'); for (const [x, y] of [[104, 90], [120, 90], [120, 100], [104, 100]]) await click(x, y); await click(104, 90);
  await shot('วาดโรงเก็บของที่ไม่มีในภาพ: สายสื่อสารผ่านอาคารนี้ ระบบเตือนให้ตรวจแนว', 3);
  await clickSel('[data-tool="scale"]'); await click(100, 16); await click(140, 16); await shot('ตั้งมาตราส่วนจากขอบถัง 40 ม. (ใช้เมื่อภาพมาจากโดรนหรือคลังภาพ)', 3);
  await fill('#scaleLen', '40'); await clickSel('#scaleOk');
  await clickSel('[data-view="report"]'); await shot('แบบรายงาน: เส้นขาวดำตามแบบ พร้อมตารางความยาว จุดข้าม และแรงดันตก', 4);
  await (await p.$('#svg')).screenshot({ path: OUT + '/sheet.png' });
  fs.writeFileSync(OUT + '/frames.json', JSON.stringify(frames)); await b.close();
})();
