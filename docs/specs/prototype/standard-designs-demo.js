// Scripted walkthrough of standard-designs.html (frames of img/stddesign_demo.mp4). Usage: node standard-designs-demo.js [outDir]
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
const OUT = process.argv[2] || 'stddesign-frames'; fs.mkdirSync(OUT, { recursive: true });
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1366, height: 1300 } });
  await p.setContent('<!doctype html><meta charset=utf-8><style>[hidden]{display:none!important}body{margin:0}</style>' +
    fs.readFileSync(path.join(__dirname, 'standard-designs.html'), 'utf8'));
  await p.waitForTimeout(600);
  const frames = []; let n = 0;
  const shot = async (cap, hold = 1) => { await p.waitForTimeout(150); const f = `${OUT}/f${String(n++).padStart(3, '0')}.png`;
    await p.screenshot({ path: f, clip: { x: 0, y: 130, width: 1366, height: 1000 } }); frames.push({ f, cap, hold }); };
  const centre = async sel => p.$eval(sel, e => { const r = e.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; });
  const tap = async sel => { const [x, y] = await centre(sel); await p.mouse.click(x, y); await p.waitForTimeout(80); };
  const at = async (xm, ym) => p.evaluate(([xm, ym]) => { const s = document.getElementById('svg'), r = s.getBoundingClientRect(), vb = s.viewBox.baseVal, T = window.__T;
    return [r.left + (T.ox + xm * T.k) / vb.width * r.width, r.top + (T.oy + ym * T.k) / vb.height * r.height]; }, [xm, ym]);
  const act = async a => tap(`[data-act="${a}"]`);

  await shot('งานใหม่ ถังน้ำใส: ยังไม่มีข้อมูลแปลน', 2);
  await p.fill('#mW', '40'); await p.fill('#mH', '40'); await shot('ใส่ขนาดที่วัดได้ 40 × 40 ม.: ระบบเรียงแบบที่ตรงไว้บนสุด', 3);
  await tap('[data-design="pwa-40x40"]'); await shot('เลือกแบบ: ช่วงเสา ช่องระบาย 12 ช่องลงถัง 6 บันได 3 ถูกเติมให้ (เส้นประ = ยังไม่ตรวจ)', 3);
  await act('ok'); await shot('ยืนยันขนาดและช่วงเสาตรงแบบ ระบบเลือกจุดถัดไปให้', 2);
  for (let i = 0; i < 3; i++) await act('ok');
  await shot('แตะ “ตรงแบบ” ทีละจุด เครื่องหมายถูกสีเขียว', 2);
  await tap('[data-id="v7"]'); await act('miss'); await shot('ช่องระบายแถว 5 ช่อง 10 ไม่มีจริง: กากบาทแดง', 3);
  const [sx, sy] = await centre('[data-id="v5"]'); await p.mouse.move(sx, sy); await p.mouse.down(); const [tx, ty] = await at(14, 18); await p.mouse.move(tx, ty, { steps: 6 }); await p.mouse.up(); await p.waitForTimeout(100);
  await shot('ลากช่องระบายไปช่องข้าง ๆ ตามที่เจอจริง: สีส้ม = ย้าย', 3);
  await tap('[data-id="h13"]'); await p.fill('#eA', '31.0'); await p.press('#eA', 'Tab'); await p.waitForTimeout(100);
  await shot('ช่องลงถังด้านบนอยู่ที่ 31.00 ม. ไม่ใช่ 29.60 ม. ตามแบบ: แก้ระยะตามผนัง', 3);
  await tap('[data-mode="add"]'); await p.selectOption('#addKind', 'ladder'); const [lx, ly] = await at(20, 40.3); await p.mouse.click(lx, ly); await p.waitForTimeout(100);
  await shot('เพิ่มบันไดด้านล่างที่ไม่มีในแบบ: สีม่วง', 3);
  await tap('#svg'); await tap('#restOk'); await shot('ยืนยันจุดที่เหลือว่าตรงแบบ: ตรวจครบ 25/25', 3);
  await tap('[data-view="diff"]'); await shot('มุมมองเทียบกับแบบ: ลูกศรจากตำแหน่งในแบบไปตำแหน่งจริง พร้อมรายการที่ต่างสำหรับรายงาน', 4);
  await p.fill('#saveName', 'ถังน้ำใส 40×40 แบบบันไดด้านล่าง'); await tap('#save'); await shot('บันทึกเป็นแบบใหม่ในคลัง: สถานีถัดไปที่เหมือนกันเลือกแบบนี้ได้เลย', 4);
  fs.writeFileSync(OUT + '/frames.json', JSON.stringify(frames)); await b.close();
})();
