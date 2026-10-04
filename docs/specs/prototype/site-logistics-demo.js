// Scripted walkthrough of site-logistics.html (frames of img/logistics_demo.mp4). Usage: node site-logistics-demo.js [outDir]
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const OUT = process.argv[2] || 'logistics-frames'; fs.mkdirSync(OUT, { recursive: true });
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1366, height: 1300 } });
  await p.setContent('<!doctype html><meta charset=utf-8><style>[hidden]{display:none!important}body{margin:0}</style>' +
    fs.readFileSync(path.join(__dirname, 'site-logistics.html'), 'utf8'));
  await p.waitForTimeout(800);
  const frames = []; let n = 0;
  const shot = async (cap, hold = 1) => { await p.waitForTimeout(150); const f = `${OUT}/f${String(n++).padStart(3, '0')}.png`;
    await p.screenshot({ path: f, clip: { x: 0, y: 130, width: 1366, height: 1100 } }); frames.push({ f, cap, hold }); };
  const at = async (xm, ym) => p.evaluate(([xm, ym]) => { const s = document.getElementById('svg'), r = s.getBoundingClientRect(), vb = s.viewBox.baseVal, px = xm / (182.74 / 640) * 1100 / 640, py = ym / (182.74 / 640) * 1100 / 640;
    return [r.left + px / vb.width * r.width, r.top + py / vb.height * r.height]; }, [xm, ym]);
  const click = async (xm, ym) => { const [x, y] = await at(xm, ym); await p.mouse.move(x, y); await p.mouse.click(x, y); await p.waitForTimeout(80); };
  const clickSel = async sel => { const q = await p.$eval(sel, e => { const r = e.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; }); await p.mouse.click(q[0], q[1]); await p.waitForTimeout(80); };
  const drag = async (sel, xm, ym) => { await clickSel(sel); await p.waitForTimeout(120);
    const q = await p.$eval(sel, e => { const r = e.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; });
    await p.mouse.move(q[0], q[1]); await p.mouse.down(); await p.waitForTimeout(80); const [x, y] = await at(xm, ym); await p.mouse.move(x, y, { steps: 8 }); await p.mouse.up(); await p.waitForTimeout(80); };
  const fill = async (sel, v) => { await p.fill(sel, String(v)); await p.press(sel, 'Tab'); await p.waitForTimeout(100); };

  await shot('ข้อมูลบนภาพสถานที่ติดตั้ง: ทางรถจากประตู จุดแคบ จุดตั้งเครน กองวัสดุ ทางขึ้น และสายไฟเหนือหัว ระบบตรวจทุกอย่างให้เอง', 3);
  await clickSel('[data-narrow="0"]'); await shot('แตะประตู: กว้าง 4.00 สูง 4.50 ม. รถทุกขนาดผ่าน', 2);
  await fill('#nW', 3.0); await shot('ถ้าประตูกว้างแค่ 3.00 ม.: รถ 10 ล้อและรถเครนเข้าไม่ได้ ตารางรถเปลี่ยนทันที', 3);
  await clickSel('#undo'); await clickSel('[data-path="1"]');
  await shot('หางพ่วง 12 ม. เข้าไม่ได้ เพราะเลี้ยวออกจากถนนกว้าง 6 ม. ไม่พอ', 3);
  await p.selectOption('#truck', 'ten'); await p.waitForTimeout(100); await shot('เปลี่ยนเป็นรถ 10 ล้อติดเครน: เข้าได้', 2);
  await clickSel('[data-crane="0"]'); await shot('แตะเครน: HIAB เอื้อมไม่ถึง 16.5 ม. ระบบเลือกรถเครน 25 ตัน ใช้พิกัด 29%', 3);
  await drag('[data-tgt="0"]', 125, 38); await shot('ลากจุดวางไปกลางถัง: รัศมี 30 ม. เกินรถ 25 ตัน ระบบเปลี่ยนเป็นรถเครน 50 ตัน', 3);
  await clickSel('#undo');
  await drag('[data-crane="0"]', 34, 88); await drag('[data-tgt="0"]', 44, 73);
  await shot('ย้ายไปยกขึ้นหลังคาอาคารสูบน้ำ: รัศมีเครนเข้าใกล้สาย 22 kV เกินระยะปลอดภัย เป็นสีแดง', 3);
  await clickSel('#undo'); await clickSel('#undo');
  await clickSel('[data-yard="0"]'); await fill('#modules', 2400); await clickSel('[data-yard="0"]');
  await shot('แผง 2,400 แผ่น: พื้นที่กองไม่พอ ระบบแนะนำให้แบ่งส่งของหลายรอบ', 3);
  await fill('#modules', 408);
  await clickSel('[data-access="1"]'); await shot('หลังคาอาคารสูบน้ำไม่มีทางขึ้น: ต้องเตรียมนั่งร้านสูง 5.5 ม.', 3);
  await clickSel('[data-tool="narrow"]'); await click(92, 84); await fill('#nLabel', 'สายโทรศัพท์พาดผ่าน'); await fill('#nH', 3.9);
  await shot('เพิ่มจุดแคบ: สายโทรศัพท์พาดผ่านทางสูง 3.90 ม. รถ 10 ล้อ (สูง 3.8 + เผื่อ 0.3) ผ่านไม่ได้', 3);
  await clickSel('[data-view="report"]'); await shot('ใบสรุปทีมติดตั้ง: ภาพขาวดำ ตารางรถ แผนเครน กองวัสดุ และรายการของที่ต้องเตรียม', 4);
  await (await p.$('#svg')).screenshot({ path: OUT + '/sheet.png' });
  fs.writeFileSync(OUT + '/frames.json', JSON.stringify(frames)); await b.close();
})();
