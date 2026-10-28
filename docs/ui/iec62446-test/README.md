# หน้าจอทดสอบ IEC 62446 ก่อน/หลังเชื่อมต่อ (iPad)

แบบหน้าจอสำหรับฟอร์ม `docs/forms/iec62446-pwa` ใช้ design system "TCRoof Survey" (`Theme.swift`) และข้อมูลจริงของสถานีจ่ายน้ำแพรกหนามแดง
เปิด `preview.html` ในเบราว์เซอร์เพื่อดูทั้ง 4 จอ (รองรับธีมมืด)

## เวอร์ชันปัจจุบันในแท็บงานติดตั้ง (iPad)

The install-page version uses the install page's shared project header and tabs. It does not draw a second IEC navigation header or pin a second action bar above the app dock. Its report content scrolls as one page, with a compact overview card (station, completion, status and setup actions), the existing inverter and stage sections, and export/submit actions at the end. The overview uses the shared `TCProgressRing` and `TCStatusChip`; overview, summary, inverter, stage, and action cards use `tcCard()` with `Space` and `Radius` tokens. The standalone IEC screen keeps its own header and pinned action bar.

| จอ | ไฟล์ | หน้าที่ | ข้อมูลใน schema |
|---|---|---|---|
| 1 ภาพรวม | `screen-1.png` | ความครบต่อ inverter แยกก่อน/หลัง, รายการที่ยังขาด, ปุ่มส่งออก Excel + Word | ทั้งไฟล์ |
| 2 ตารางสตริง | `screen-2.png` | กริด 10 MPPT × 2 ช่อง เรียงเหมือนคอลัมน์ E..X ของ Excel แสดงป้ายรูป ST(n) คู่กับเลขช่อง | `inverters[].strings[].before/after`, `before.continuity` |
| 3 กรอกทีละสตริง | `screen-3.png` | รูปแรงดัน + กระแสแบบหน้า Word, แป้นตัวเลข, ค่า IR +E/−E, เช็คค่ากับค่าคาดหมาย | `strings[].photos`, `strings[].before.*` |
| 4 ผลการผลิต | `screen-4.png` | กรอกพลังงาน 7 วันและ Yr แล้วคำนวณ Yf / PR / ประสิทธิภาพ, เทียบกับค่าที่กรอกในฟอร์มเดิม | `inverters[].after`, `conditions.after` |

## หลักที่ใช้
- **จอเดียวกับแผ่นงาน**: แถบสีเขียว `paper-band` และลำดับคอลัมน์เหมือน Excel
- **ช่องที่ฟอร์มเดิมปล่อยว่าง** (IR MΩ, Vmp/Imp, ผ่าน/ไม่ผ่าน, วันที่/ผู้ทดสอบ/เครื่องมือ) แสดงเป็น "ยังขาด" สี `pending` พร้อมจุด
- **ค่าคำนวณห้ามกรอกเอง**: kWp, Yf, PR, พลังงานเฉลี่ยต่อวัน, System Efficiency
- **เช็ค Voc อัตโนมัติ**: เทียบกับค่ากลางของสตริงที่มีจำนวนแผงเท่ากัน เกิน 5% ขึ้นเตือน
- **ป้ายรูป**: Word ใช้ `INV{i}ST{seq}` นับเฉพาะสตริงที่ใช้งาน ส่วน Excel ใช้เลขช่อง 1–20 จอ 2 แสดงทั้งสองแบบ

## ค่าที่ยังเป็นสมมติฐาน
- เกณฑ์ PR ผ่านที่ 0.70 (ตั้งค่าได้) ยังไม่มีในฟอร์มของ กปภ.
- สถานะความคืบหน้าและเวลาในจอเป็นตัวอย่าง ค่าที่วัดทั้งหมดมาจากฟอร์มจริง
