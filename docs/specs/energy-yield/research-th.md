# ใช้ PVGIS คำนวณ ลดตัวเลขด้วยข้อมูลดาวเทียม แล้วแสดงช่วงความไม่แน่นอนตรงไปตรงมา

**คำตอบสั้น:** สำหรับฟีเจอร์ "Preliminary Energy Yield" ใน TCRoof ให้ใช้ **PVGIS v5.3 `PVcalc`** เป็นแหล่งหลัก เรียกแยกทีละ roof face ด้วย tilt/azimuth ที่วัดจริง และตั้ง `loss=0` เพื่อให้แอปคุม loss chain เอง จากนั้นปรับระดับรังสีด้วย **Global Solar Atlas (Solargis)** ซึ่งเป็นข้อมูลดาวเทียม เพราะในประเทศไทย PVGIS ใช้ได้เฉพาะ **PVGIS-ERA5** (reanalysis ปี 2005–2023) ไม่ใช่ SARAH ข้อมูลชุดนี้มีแนวโน้มให้ค่ารังสีสูงเกินจริงในเขตร้อนชื้น ส่วน Open-Meteo **ไม่เหมาะเป็นแหล่งหลัก** เพราะ free tier ห้ามใช้เชิงพาณิชย์ และ Historical/Satellite API ต้องซื้อแพ็กเกจ Professional ขึ้นไป ตัวเลขใน draft มีปัญหาเชิงตรรกะอยู่หนึ่งจุด คือ **PR 78–80% ดูเหมือนคำนวณจาก GHI ไม่ใช่ POA** (1,450 ÷ 1,850 = 78.4%) ถ้าคิดตาม IEC 61724-1 บนฐาน POA ค่า PR ของระบบหลังคาไทยที่สมจริงอยู่ราว **73–78% (ค่ากลาง ~76%)** specific yield ของหลังคาเมทัลชีทลาดต่ำที่หันทิศดีอยู่ราว **1,330–1,430 kWh/kWp/yr** ส่วน 1,450 คือกรณีดีที่สุด สำหรับระบบ ~80 kWp ค่า P50 ที่ควรแสดงจึงอยู่ราว **106,000–114,000 kWh/yr** ไม่ใช่ 116,000 และควรแสดง P90 คู่กันที่ประมาณ **−10% ถึง −13%** ตัวเลขปีแรกไม่ใช่ปัญหาใหญ่ เพราะต่างจาก PVsyst เพียงไม่กี่เปอร์เซ็นต์ ความเสี่ยงที่แท้จริงอยู่ที่สามเรื่อง ได้แก่ การหัก loss ซ้ำกับ PVGIS การวัด azimuth ผิดหน้าหลังคาเพราะ compass ถูกรบกวนบนหลังคาเหล็ก และการนำเสนอ P50 ราวกับเป็นตัวเลขรับประกัน

## ในประเทศไทย PVGIS เหลือแค่ ERA5 และ Open-Meteo ติดเงื่อนไขเชิงพาณิชย์

### PVGIS v5.3: ฟรี เรียกครั้งเดียวได้ผล kWh ครบ แต่ข้อมูลเป็น reanalysis

`PVcalc` เป็น GET เดียวที่ `https://re.jrc.ec.europa.eu/api/v5_3/PVcalc` รับพารามิเตอร์บังคับ `lat`, `lon`, `peakpower` (kWp) และ `loss` (%) พร้อมพารามิเตอร์เสริม `angle` (tilt) และ `aspect` (azimuth แบบ **0 = S, 90 = W, −90 = E**) ค่าเริ่มต้นของผลลัพธ์คือ **CSV จึงต้องส่ง `outputformat=json` เสมอ** ([PVGIS API docs](https://joint-research-centre.ec.europa.eu/photovoltaic-geographical-information-system-pvgis/getting-started-pvgis/api-non-interactive-service_en)) ผลลัพธ์ให้ `E_y`, `H(i)_y` (POA kWh/m²/yr), `SD_y` (ส่วนเบี่ยงเบนมาตรฐานระหว่างปี) และ loss แยกเป็นรายการ ได้แก่ `l_aoi`, `l_spec`, `l_tg`, `l_total` ข้อควรระวังเชิงโค้ดคือ **`l_spec` ถูกส่งกลับมาเป็น string** (เช่น `"0.86"`) ขณะที่ฟิลด์อื่นเป็นตัวเลข และ `PVcalc` ไม่มี `startyear/endyear` เพราะใช้ค่าเฉลี่ยตลอดช่วงข้อมูลเสมอ ([live test](https://re.jrc.ec.europa.eu/api/v5_3/PVcalc?lat=13.75&lon=100.5&peakpower=5&loss=14&angle=15&aspect=0&outputformat=json))

ข้อเท็จจริงสำคัญที่สุดสำหรับไทย: เอกสารระบุว่า Asia ใช้ SARAH3 เป็นค่าเริ่มต้น แต่เมื่อทดสอบจริงที่กรุงเทพฯ การส่ง `raddatabase=PVGIS-SARAH3` ได้ HTTP 400 "Location out of the spatial coverage" ส่วน `PVGIS-SARAH2` และ `PVGIS-NSRDB` ถือเป็นค่าที่ไม่ถูกต้องใน v5.3 **ฐานข้อมูลเดียวที่ใช้ได้ในไทยคือ PVGIS-ERA5 ปี 2005–2023 ความละเอียด ~0.25°** โดยมี DEM horizon (SRTM 90 m) เปิดใช้เป็นค่าเริ่มต้น ([PVGIS API docs](https://joint-research-centre.ec.europa.eu/photovoltaic-geographical-information-system-pvgis/getting-started-pvgis/api-non-interactive-service_en); [PVGIS 5.3 release](https://joint-research-centre.ec.europa.eu/photovoltaic-geographical-information-system-pvgis/pvgis-releases/pvgis-53_en)) DEM horizon คิดเฉพาะภูมิประเทศ ไม่รวมอาคารหรือต้นไม้ ในตัวเมืองเชียงใหม่ การเปิดหรือปิด horizon เปลี่ยน E_y เพียง 1376.85 → 1376.89 kWh/kWp ดังนั้นเงาจากสิ่งกีดขวางใกล้ต้องส่งเข้าไปเองผ่าน `userhorizon` ซึ่งเป็นรายการความสูงของ horizon ที่ระยะ azimuth เท่ากัน **เริ่มจากทิศเหนือและวนตามเข็มนาฬิกา**

แบบจำลองของ PVGIS ใช้สมการกำลังของ Huld (2011) กับอุณหภูมิโมดูลแบบ Faiman ค่า U ของ `mountingplace=free` คือ U0 = 26.9, U1 = 6.2 ส่วน `building` คือ U0 = 20.0, U1 = 3.2 ค่า AOI ใช้แบบจำลอง Martin & Ruiz ส่วน **inverter, สายไฟ และ mismatch ไม่ได้ถูกจำลอง** ทั้งหมดต้องใส่รวมไว้ใน `loss` และค่าแนะนำ 14% ก็รวมการเสื่อมสภาพราว 0.5%/ปีไว้ด้วย ([PVGIS calc methods](https://joint-research-centre.ec.europa.eu/photovoltaic-geographical-information-system-pvgis/getting-started-pvgis/pvgis-data-sources-calculation-methods_en)) ตั้งแต่ 2025-09-05 มีตัวเลือก `pvtechchoice=crystSi2025` ซึ่งใช้สัมประสิทธิ์ใหม่ที่อาจให้ค่าสูงขึ้นเล็กน้อย แต่ค่าเริ่มต้นยังเป็น `crystSi` แบบเดิม ([PVGIS updates](https://joint-research-centre.ec.europa.eu/photovoltaic-geographical-information-system-pvgis/pvgis-releases/updates-bug-fixes-and-history_en))

เงื่อนไขการใช้งานผ่อนปรนมาก ไม่ต้องใช้ key และไม่ต้องลงทะเบียน จำกัด **30 req/s ต่อ IP** (เกินแล้วได้ 429 และได้ 529 เมื่อระบบโหลดเกิน) ไม่มี CORS แต่ไม่กระทบการเรียกจาก `URLSession` ใน native iOS ([PVGIS API docs](https://joint-research-centre.ec.europa.eu/photovoltaic-geographical-information-system-pvgis/getting-started-pvgis/api-non-interactive-service_en)) **ไม่พบข้อความที่ห้ามใช้เชิงพาณิชย์ และไม่มี SLA** ฐานทางกฎหมายที่น่าจะใช้คือนโยบาย reuse ของคณะกรรมาธิการยุโรป ([Decision 2011/833/EU](https://eur-lex.europa.eu/eli/dec/2011/833/oj)) ซึ่งโดยทั่วไปอนุญาตให้ใช้เชิงพาณิชย์ได้เมื่ออ้างอิงแหล่งที่มา แต่ทีมวิจัยยังเปิดหน้า "Usage Conditions" ของ PVGIS ไม่ได้ จึงควรตรวจสอบข้อความจริงก่อนเปิดใช้ ในการทดสอบจริง latency อยู่ที่ ~1 วินาทีต่อ `PVcalc` (~5 KB) และ 2 ใน ~20 คำขอเจอ connection reset ซึ่งหายเมื่อ retry ควร pin path `/api/v5_3/` เสมอ เพราะ path ที่ไม่ระบุเวอร์ชันชี้ไป 5.2 "เพียงช่วงหนึ่ง" ส่วน PVGIS 6 ยังเป็น beta ที่ใช้ API ต่างออกไป ([PVGIS home](https://joint-research-centre.ec.europa.eu/photovoltaic-geographical-information-system-pvgis_en))

### Open-Meteo: ข้อมูลดาวเทียม Himawari ละเอียดกว่า แต่ต้องทำ PV model เองและต้องจ่ายเงิน

Open-Meteo ให้ `global_tilted_irradiance` พร้อม `tilt` และ `azimuth` โดยใช้ convention เดียวกับ PVGIS (0 = S, −90 = E) ใช้ได้กับ forecast, historical archive และ Satellite Radiation API ที่ `satellite-api.open-meteo.com/v1/archive` ซึ่งมี **JMA/JAXA Himawari ความละเอียด 0.05° (~5 km) ทุก 10 นาที** ครอบคลุมเอเชีย ส่วน historical มี ERA5 (0.25°, 1940–ปัจจุบัน) และ ECMWF IFS (9 km, 2017–ปัจจุบัน) ([Open-Meteo historical docs](https://open-meteo.com/en/docs/historical-weather-api); [satellite radiation docs](https://open-meteo.com/en/docs/satellite-radiation-api)) GTI คำนวณด้วย isotropic sky และ albedo คงที่ 20% ค่ารังสีเป็นค่าเฉลี่ยย้อนหลังของชั่วโมงก่อนหน้า เอกสารเรื่องปีเริ่มต้นของ Himawari ขัดกันเอง (ตารางบอก 2015 ส่วนรายการแหล่งข้อมูลบอก 2023) และการทดสอบจริงพบว่า `era5_land` ให้รังสีเป็น **null** ที่กรุงเทพฯ ข้อเสียหลักคือ Open-Meteo ให้เฉพาะ irradiance แอปต้องเขียนแบบจำลองอุณหภูมิ, AOI และ loss เอง

เรื่องลิขสิทธิ์เป็นตัวตัดสิน **free API ใช้ได้เฉพาะงานไม่เชิงพาณิชย์** แอปของบริษัทหรือเครื่องมือของผู้รับเหมาถือเป็นเชิงพาณิชย์ ([Open-Meteo terms](https://open-meteo.com/en/terms)) แพ็กเกจ API Standard **ไม่มี** historical, climate และ satellite API ต้องเป็น **API Professional ขึ้นไป** ([Open-Meteo pricing](https://open-meteo.com/en/pricing)) ราคาที่ประกาศไว้เมื่อ มิ.ย. 2023 คือ Standard USD 29/เดือน และ Professional USD 99/เดือน ([Open-Meteo Substack](https://openmeteo.substack.com/p/api-subscriptions-for-commercial)) แต่หน้าราคาปัจจุบันไม่แสดงตัวเลข จึงต้องยืนยันอีกครั้ง ข้อมูลอยู่ภายใต้ CC BY 4.0 และ server เป็น AGPLv3 ที่ self-host ได้ แต่ทางนั้นต้องดูแลข้อมูล ERA5/Himawari เอง นอกจากนี้ คำขอที่ยาวเกิน 2 สัปดาห์นับเป็นหลาย call ([pricing](https://open-meteo.com/en/pricing)) คำขอ GTI รายชั่วโมง 10 ปีจึงกินโควตาราว ~260 call ต่อการประมาณหนึ่งครั้ง (ตัวเลขนี้อนุมานจากสูตรถ่วงน้ำหนักที่ยังไม่ชัดเจน)

### ทางเลือกอื่นเปรียบเทียบกัน

| แหล่ง | สถานะในไทย | ทำ PV sim / รับ tilt-azimuth | เงื่อนไข / ราคา | บทบาทที่เหมาะ |
|---|---|---|---|---|
| **PVGIS v5.3** | ERA5 เท่านั้น 2005–2023 | ใช่ / ใช่ | ฟรี ไม่มี key ไม่มี SLA | **หลัก** |
| **Global Solar Atlas** (Solargis) | ข้อมูลถึงปี 2025, layer 2.2.68 | PVOUT เฉพาะมุม tilt ที่เหมาะสมที่สุด / ไม่รับ | CC BY 4.0 แต่ endpoint ไม่มีเอกสารและไม่มี SLA | **cross-check / ปรับระดับรังสี** |
| **PVWatts v8** `dataset=nsrdb` | NSRDB Himawari TMY-2020, 4 km | ใช่ / ใช่ | ฟรีด้วย key, 1,000 req/h, terms เชิงพาณิชย์นอก US ยังไม่ยืนยัน | fallback ออนไลน์ |
| **Open-Meteo** | Himawari 5 km, ERA5, IFS | ไม่ / ใช่ (GTI) | Professional ขึ้นไปสำหรับข้อมูลย้อนหลัง | ใช้เมื่อต้องการ time series ล่าสุด |
| **Solargis API** | Himawari, bankable | ใช่ / ใช่ | Prospect EUR 2,400–4,800/yr, API ต้องขอใบเสนอราคา | ขั้น bankable |
| **Solcast** | Himawari 1–2 km | ใช่ / ใช่ | ขอใบเสนอราคาเท่านั้น, free/hobbyist ห้ามใช้เชิงพาณิชย์ | ขั้น bankable, นำเข้า PVsyst ได้ตรง |
| **Meteonorm API** | ทั่วโลก | ใช่ (`pv_production`) / ใช่ | ขอใบเสนอราคา, demo key ไม่มีจุดในไทย | ให้ตรงกับค่าเริ่มต้นของ PVsyst |
| **NASA POWER** | 1° × 1° | ไม่ / ไม่ | ฟรี ไม่มี key | sanity check เท่านั้น |
| **DEDE/TMD** | แผนที่วิจัย | ไม่ | ไม่มี API สาธารณะ | อ้างอิงในรายงานภาษาไทย |

ที่มาของตาราง: PVWatts รันได้จริงกับพิกัดไทย ได้ cell NSRDB "Bangkok Metropolis" และ **1,400 kWh/kWp** ที่ 15°S, loss 14% ([live request](https://developer.nlr.gov/api/pvwatts/v8.json?api_key=DEMO_KEY&lat=13.7563&lon=100.5018&system_capacity=1&module_type=0&losses=14&array_type=1&tilt=15&azimuth=180&dataset=nsrdb)) ควรรู้ด้วยว่า NREL เปลี่ยนชื่อเป็น National Laboratory of the Rockies และ host ที่ใช้ได้ตอนนี้คือ `developer.nlr.gov` ([energy.gov](https://www.energy.gov/eere/articles/energy-department-renames-nrel-national-lab-rockies)) GSA endpoint `api.globalsolaratlas.info/data/lta?loc=lat,lng` ให้ค่าที่กรุงเทพฯ **GHI 1,794 kWh/m², GTI_opta 1,841.7, OPTA 15°, PVOUT 1,447.9 kWh/kWp** ([live request](https://api.globalsolaratlas.info/data/lta?loc=13.7563,100.5018)) และอยู่ภายใต้ CC BY 4.0 ([World Bank Data Catalog](https://datacatalog.worldbank.org/search/dataset/0038509/global-solar-atlas-application)) ราคา Solargis มาจากบทวิจารณ์ของบุคคลที่สาม ([Heaven Green Energy](https://www.heavengreenenergy.com/blog/solargis-review)) ส่วน Solcast จำกัด hobbyist ไว้ที่ "non-commercial home use" ([Solcast terms](https://solcast.com/terms-of-use)) NASA POWER ให้ GHI กรุงเทพฯ 5.23 kWh/m²/day (~1,910/yr) สูงกว่า GSA ราว 6% ([live request](https://power.larc.nasa.gov/api/temporal/climatology/point?parameters=ALLSKY_SFC_SW_DWN&community=RE&longitude=100.5018&latitude=13.7563&format=JSON)) PVsyst นำเข้าข้อมูล Solcast TMY ได้โดยตรง ([Solcast KB](https://kb.solcast.com.au/pvsyst)) และนำเข้าไฟล์ Solargis ได้ ([Solargis KB](https://kb.solargis.com/docs/solargis-data-in-pvsyst)) ส่วนแหล่ง meteo เริ่มต้นของ PVsyst ที่เข้าใจกันว่าเป็น Meteonorm ยังไม่ได้ยืนยันในรอบนี้

## ERA5 ให้รังสีสูงกว่าข้อมูลดาวเทียมราว 5% ที่กรุงเทพฯ

ยังไม่มีงานวิจัยที่ peer-review แล้วเปรียบเทียบ PVGIS-ERA5, Solargis, Solcast หรือ Meteonorm กับสถานีภาคพื้นดินในไทยแบบเป็นตัวเลข หลักฐานในไทยมาจากแบบจำลองดาวเทียมของกลุ่ม ม.ศิลปากร ซึ่งมี **RMSD 6.1% และ MBD 0.3%** บน GHI เฉลี่ยรายเดือนที่ 38 สถานี ([Janjai et al.](https://www.nepjol.info/index.php/JIE/article/view/5939)) และแบบจำลองกึ่งเอมพิริคัลที่ได้ RMSE 6.9% บน 36 สถานีอิสระ ([Chanalert et al. 2022](https://li01.tci-thaijo.org/index.php/sehs/article/view/256713)) ส่วน reanalysis มีหลักฐานชัดว่าให้ค่าสูงเกินในเขตร้อนชื้น GLDAS เทียบกับ 5 สถานีในภาคใต้มี **MBD +15.8%** และสถานีระนองมี RMSD สูงถึง 35.6% ([Sabooding et al. 2025](https://www.frontiersin.org/journals/environmental-science/articles/10.3389/fenvs.2025.1657447/full)) สำหรับ ERA5 เอง ทั่วโลกมี bias +4 W/m² แต่ **ให้ค่าสูงเกินเมื่อมีเมฆและต่ำกว่าเล็กน้อยเมื่อฟ้าใส** ([Urraca et al. 2018](https://publications.jrc.ec.europa.eu/repository/handle/JRC108636)) ในเขตร้อนชื้นของแอฟริกาตะวันตก rMBD รายชั่วโมงเมื่อมีเมฆสูงถึง 28% ([Kakou et al. 2025](https://jahrbib.sulb.uni-saarland.de/handle/20.500.11880/39859)) มีข้อสังเกตแย้งอยู่หนึ่งชิ้น คือโปสเตอร์ของ KMUTT/CES ปี 2024 รายงานว่า ERA5 *ต่ำกว่า* ค่าวัดใกล้กรุงเทพฯ ([Yahaya et al. 2024](https://kirim.kmutt.ac.th/converis/portal/detail/Publication/1481496311?lang=en_GB)) ทิศทางของ bias จึงอาจต่างกันตามพื้นที่ แต่ข้อสรุปของผู้วิจัยตรงกันว่าควรปรับแก้ ERA5 ก่อนใช้

ฝั่งดาวเทียมทำได้ดีกว่ามาก Solargis มี mean GHI bias ที่ 91 สถานีในเขตร้อน **+1.5% (SD 3.4%)** ([Solargis validation](https://kb.solargis.com/docs/validation-of-solar-irradiance-data)) แต่ก็จัดเอเชียตะวันออกเฉียงใต้เข้ากลุ่มที่มีความไม่แน่นอนสูงสุด คือ **P90 ±8%** ([Solargis uncertainty](https://kb.solargis.com/docs/uncertainty-estimates)) Solcast ที่ 21 สถานีในเขตร้อนชื้นมี bias +0.5% ขณะที่ ERA5 ใน 70 สถานีมี bias +2.4% ([Solcast validation](https://solcast.com/validation-and-accuracy) ซึ่งเป็นข้อมูลจากผู้ขายเอง) เมื่อเทียบตัวเลขที่กรุงเทพฯ โดยตรง ระนาบเอียงราว 15° ทิศใต้ได้ค่าดังนี้: PVGIS-ERA5 **1,937 kWh/m²**, GSA GTI_opta **1,842 kWh/m²** และ Open-Meteo archive เฉลี่ย 10 ปี 1,899 kWh/m² ERA5 จึงสูงกว่าข้อมูลดาวเทียมของ Solargis ราว **5%** ตัวเลขนี้คือเหตุผลหลักที่ควรปรับระดับรังสีของ PVGIS ลงด้วย GSA ในทางกลับกัน หลักฐานเชิงยีลด์ในภูมิภาคไม่ได้แย่ PVGIS ทำนาย rooftop 4.5 kWp ที่สุราบายาคลาดเพียง **+1.52%** ต่อปี ([JREE, Surabaya](https://doaji.irandoc.ac.ir/home/article?id=107741)) แต่หลักฐานนี้มาจากระบบเดียว

ในระดับประเทศ แผนที่ DEDE/ศิลปากรให้ค่าเฉลี่ยทั้งประเทศ **18.2 MJ/m²/day ≈ 1,846 kWh/m²/yr** โดยพื้นที่ดีที่สุด (อีสานตอนล่างและภาคกลางตอนบน) อยู่ที่ 19–20 MJ ≈ 1,930–2,030 kWh/m²/yr ([EPPO/DEDE](https://eppo.go.th/images/Power/renewable-energy/19.pdf)) ช่วงความแปรปรวนระหว่างปีที่ PVGIS-ERA5 ให้ (`SD_y`) มีเพียง **1.7–3.2%** (กรุงเทพฯ 2.0%, เชียงใหม่ 3.2%) ([PVGIS API](https://re.jrc.ec.europa.eu/api/v5_3/PVcalc?lat=18.79&lon=98.98&peakpower=1&loss=14&angle=10&aspect=0&outputformat=json)) แต่ Solargis รายงานว่าปี 2023 เอเชียตะวันออกเฉียงใต้มีรังสีสูงกว่าค่าเฉลี่ยระยะยาว **~10%** ([PV Tech](https://pv-tech.org/solargis-solar-irradiance-in-southeast-asia-10-higher-than-average-in-2023)) แสดงว่าปีเดี่ยวๆ อาจแกว่งได้มากกว่าที่ SD_y บ่งบอก

## PR ที่สมจริงของหลังคาไทยคือ ~76% บนฐาน POA ไม่ใช่ 78–80%

### นิยาม PR ที่ถูกต้อง และการคำนวณจาก PVGIS

ตาม IEC 61724-1 (ในรูปที่ NREL เรียบเรียงใหม่) **PR = Yf / Yr = (E_AC / P_STC) / (H_POA / 1 kW/m²)** ซึ่งต้องใช้รังสีบนระนาบแผง (POA) ([NREL Dierauf et al. 2013](https://www.nrel.gov/docs/fy13osti/57991.pdf)) "PR" ที่คิดจาก GHI จะรวม transposition gain เข้ามาปนกับประสิทธิภาพระบบ ทำให้เทียบข้ามหลังคาไม่ได้ จากผลลัพธ์ของ PVGIS คำนวณได้ตรงๆ ว่า **PR = E_y / (peakpower × H(i)_y)** ตัวอย่างกรุงเทพฯ 10°S: 1,446.4 / 1,927.4 = **75.0%** ซึ่งเท่ากับ 1 + `l_total`/100 ([PVGIS API](https://re.jrc.ec.europa.eu/api/v5_3/PVcalc?lat=13.75&lon=100.5&peakpower=1&loss=14&angle=10&aspect=0&outputformat=json)) ถ้าจะนำ PR ไปเทียบกับข้อมูลจากระบบ monitoring ในภายหลัง ควรใช้ temperature-corrected PR เพราะอุณหภูมิอย่างเดียวทำให้ PR แกว่งตามฤดูได้ถึง ±10% ([NREL](https://www.nrel.gov/docs/fy13osti/57991.pdf))

### ข้อมูลวัดจริงในไทยรวมกันอยู่ที่ 71–77%

ระบบ rooftop 1 MW ที่สมุทรสงครามวัดได้ **PR 77.2%** (PVsyst ทำนาย 75.6%) ขณะที่ระบบภาคพื้นดินที่ใช้อุปกรณ์เหมือนกันได้ 83.0% ความต่างนี้ส่วนใหญ่มาจากอุณหภูมิ ระบบบนหลังคายังเสื่อมเร็วกว่า **0.62%/yr** เทียบกับ 0.42%/yr ([RMUTT](https://research.rmutt.ac.th/?p=19666)) ระบบ 32.4 kWp ในกรุงเทพฯ มี **PR 0.712** ([TEE Journal](https://ph04.tci-thaijo.org/index.php/TEE_J/article/view/7696)) ระบบบ้าน 9.8 kWp ในภาคเหนือที่หัน S/W, W และ E มี PR ราว 70–80% และ yield ราว 1,250–1,315 kWh/kWp/yr ([KMUTT](https://kirim.kmutt.ac.th/converis/portal/detail/Publication/601031074?lang=en_GB)) ระบบ 3.5 kWp ที่ตากได้ ≈1,391 kWh/kWp/yr ([IMECS 2016](https://www.iaeng.org/publication/IMECS2016/IMECS2016_pp572-575.pdf)) ด้าน PVGIS เอง (loss 14%) ให้ **PR ราว 75% แบบ free-standing** และ **72.2% แบบ building** โดย thermal loss ที่กรุงเทพฯ เพิ่มจาก −11.1% เป็น −14.5% ([PVGIS API building](https://re.jrc.ec.europa.eu/api/v5_3/PVcalc?lat=13.75&lon=100.5&peakpower=1&loss=14&angle=10&aspect=0&mountingplace=building&outputformat=json)) โมดูลรุ่นใหม่อย่าง TOPCon/PERC มีสัมประสิทธิ์อุณหภูมิดีกว่าโมดูล poly ในงานวิจัยเก่า อาจเพิ่ม PR ได้ 1–2 จุด แต่ข้อนี้ยังไม่มีข้อมูลภาคสนามในไทยยืนยัน

### Loss breakdown สำหรับหลังคาเมทัลชีทในเขตร้อน

อุณหภูมิเป็น loss ใหญ่ที่สุดในไทย ประมาณ **11% เมื่อติดตั้งแบบระบายอากาศดี และ 14–15% เมื่อติดชิดหลังคาเหล็ก** เทียบกับเพียง ~2.5% ในตัวอย่างเขตอบอุ่นของ IEA PVPS ([IEA PVPS T13-18](https://iea-pvps.org/wp-content/uploads/2021/01/Executive-Summary-IEA-PVPS-T13-18_2020-Uncertainties-in-Yield-Assessments-and-PV-LCOE.pdf)) soiling ในไทยสะสมสูงสุดในเดือนมกราคม (เฉลี่ย 0.47%/วัน) และแทบเป็นศูนย์ช่วงฝน ในบางพื้นที่สูญเสียได้ถึง 3% ต่อเดือน ([KMUTT soiling](https://kirim.kmutt.ac.th/converis/portal/detail/Publication/1478036503?lang=en_GB)) ตารางด้านล่างคือค่าเริ่มต้นที่เสนอ แบ่งเป็นสองกลุ่มเพื่อกันการหักซ้ำ

| กลุ่ม | Loss | ค่าเริ่มต้น | ช่วง | หมายเหตุ |
|---|---|---|---|---|
| **A: PVGIS คิดให้แล้ว** | IAM/reflection (`l_aoi`) | ~2.7% | 2–3.5% | ห้ามหักซ้ำ |
| | Spectral (`l_spec`) | ~+0.9% (เป็น gain) | ±1% | ห้ามหักซ้ำ |
| | Temperature + low irradiance (`l_tg`) | 11% (free) – 14.5% (building) | 10–15% | เลือกผ่าน `mountingplace` |
| **B: แอปต้องหักเอง** | Soiling | 3% | 2–5% | ใกล้ไร่ เหมือง หรือถนน ใช้ 4–5% |
| | LID/module quality | 1% | 0.5–2% | IEA PVPS survey |
| | Mismatch | 1% | 1–2% | |
| | DC wiring | 1.5% | 1–2% | |
| | Inverter | 2.5% | 1.5–3% | |
| | AC wiring | 0.5% | 0.5–1% | |
| | Clipping (DC/AC ≤ 1.2) | 0.5% | 0–2% | เพิ่มเมื่อ DC/AC > 1.3 |
| | Availability | 1% | 0.5–2% | |
| | **ผลคูณกลุ่ม B** | **≈ 0.895** | | ไม่รวม shading และ degradation |

ตัวเลขกลุ่ม B สำหรับ mismatch, wiring, availability และ clipping ยังไม่มีแหล่งอ้างอิงเฉพาะไทย ([IEA PVPS T13 2017](https://iea-pvps.org/wp-content/uploads/2020/01/Uncertainties_in_PV_System_Yield_Predictions_and_Assessments_by_Task_13.pdf)) เมื่อคูณกลุ่ม A ของ PVGIS ที่กรุงเทพฯ 10°S (`loss=0` ได้ ~87.3% แบบ free และ ~84.0% แบบ building) เข้ากับกลุ่ม B 0.895 จะได้ **PR ≈ 78.1% (free) และ 75.1% (building)** ค่ากลาง ~76.6% สอดคล้องกับค่าวัดจริงในไทย ระบบที่ยกรางบนหลังคาเมทัลชีททั่วไปอยู่ระหว่างสองค่านี้

## ตัวเลขใน draft: GHI ใช้ได้ แต่ PR คิดผิดฐาน และพลังงานสูงไป 2–8%

| ค่าใน draft | ประเมิน | ค่าที่แนะนำ (80 kWp, ภาคกลาง) |
|---|---|---|
| GHI ~1,850 kWh/m²/yr | **ใช้ได้เป็นค่ากลางระดับประเทศ** (DEDE 1,846) แต่สูงไปสำหรับกรุงเทพฯ เมื่อเทียบ GSA 1,794 และต่ำไปสำหรับอีสานตอนล่าง (GSA โคราช 1,898) | ใช้ค่าตามพิกัดจาก GSA ไม่ใช้ค่าคงที่ระดับประเทศ |
| Specific yield 1,450 kWh/kWp/yr | **เป็นกรณีดีที่สุด** ของ PVGIS-ERA5 ที่มุมเหมาะสมที่สุดแบบ free-standing ซึ่ง ERA5 เองก็น่าจะสูงเกินอยู่แล้ว | **~1,330–1,430** (P50) ขึ้นกับ mounting, ทิศ และ tilt |
| PR 78–80% | **ไม่สอดคล้องภายใน**: 1,450/1,850 = 78.4% คือ PR บนฐาน GHI ถ้าคิดบน POA (~1,840–1,930) จะได้ 75–79% | **~76%** (ช่วง 73–78%) บนฐาน POA |
| ~116,000 kWh/yr (≈80 kWp) | สูงไปราว 2–8% และไม่มี P90 | **P50 ≈ 106,000–114,000**, **P90 ≈ 95,000–102,000** |

ตัวเลขฝั่งแนะนำคำนวณดังนี้ ใช้ H(i) ของ PVGIS ที่กรุงเทพฯ 10°S (1,927 kWh/m²) คูณ resource scaling factor จาก GSA ≈ 0.95 ได้ POA ≈ 1,832 kWh/m² คูณ PR 75–78% ได้ **1,377–1,431 kWh/kWp** หรือ **110–114 MWh** สำหรับ 80 kWp หลังคาที่ลาดเพียง 3–5° หรือหันตะวันออก/ตะวันตกจะต่ำลงอีก 1–5% จึงได้ขอบล่าง ~106 MWh ส่วน P90 ใช้ตัวคูณ 0.87–0.90 ดังที่อธิบายในหัวข้อถัดไป ถ้าระบบอยู่อีสานตอนล่างหรือภาคกลางตอนบน ค่า 1,450 อาจเกิดขึ้นจริงได้ (GSA PVOUT โคราช 1,548.6 kWh/kWp ที่ optimum tilt ([live request](https://api.globalsolaratlas.info/data/lta?loc=14.97,102.10))) แต่ PR ก็ยังควรรายงานบนฐาน POA

## Tilt วัดง่าย azimuth คือจุดเสี่ยง และความไม่แน่นอนต้องแสดงเป็น P50/P90

### ความไวของ yield ต่อมุมในไทยต่ำมาก ยกเว้นวัดผิดหน้าหลังคา

ผลจาก PVGIS ที่กรุงเทพฯ แสดงว่าพื้นผิว yield แบนมาก มุมเหมาะสมที่สุดคือ **17°, azimuth −12°** (เยื้องไปทางตะวันออกเล็กน้อย) ได้ 1,455.5 kWh/kWp ที่ tilt 10° การวัด azimuth คลาด ±5° เปลี่ยน yield เพียง ~0.1% ส่วนที่ 15° การคลาด 20° ทำให้เสีย 0.6% แต่ความผิดพลาดหยาบๆ มีผลมาก ที่ 15° หันทิศเหนือได้ 1,289 (**−11%**) หันตะวันตกได้ 1,365 (−6%) และหันตะวันออกได้ 1,396 ที่ 30° หันทิศเหนือได้เพียง 1,103 (−23%) **หลังคาที่หันตะวันออกได้มากกว่าตะวันตก ~1.5–2.5%** ทุกพื้นที่ภาคกลาง อีสาน และเหนือ ([PVGIS API](https://re.jrc.ec.europa.eu/api/v5_3/PVcalc?lat=13.75&lon=100.5&peakpower=1&loss=14&angle=10&aspect=-90&outputformat=json); [PVGIS API docs](https://joint-research-centre.ec.europa.eu/photovoltaic-geographical-information-system-pvgis/getting-started-pvgis/api-non-interactive-service_en)) เป้าความแม่นที่พอเพียงจึงเป็น **tilt ±2° และ azimuth ±5–10°** ข้อสำคัญที่สุดคือต้องไม่สลับหน้าหลังคา โดยเฉพาะหลังคาจั่วที่หันตะวันออก/ตะวันตก

**Tilt** วัดจาก `CMDeviceMotion.gravity` ในเฟรม `.xArbitraryZVertical` ซึ่งไม่ใช้ magnetometer คำนวณ β = acos(|g_z|) จากค่าเฉลี่ย 1–2 วินาทีขณะเครื่องนิ่ง และทำ flip-average 180° เพื่อหักล้าง offset จาก camera bump ([Apple CMAttitudeReferenceFrame](https://developer.apple.com/documentation/coremotion/cmattitudereferenceframe.md)) ยังไม่มีงานวิจัยที่ระบุความแม่นยำของ inclinometer บน iPhone/iPad รุ่นปัจจุบัน ค่า ±0.5–1° จึงเป็นการอนุมาน แต่ก็เพียงพอ **Azimuth** มีปัญหาจริง `trueHeading` ปรับ declination ให้อัตโนมัติเมื่อเปิด location updates และ declination ในไทยเองน้อยมาก (−0.2° ถึง −1.0° ตาม WMM2025) แต่ `headingAccuracy` ตรวจจับ bias คงที่จากมวลเหล็กไม่ได้ ([Apple headingAccuracy](https://developer.apple.com/documentation/corelocation/clheading/headingaccuracy.md)) เคยมีกรณีบน Apple Forums ที่ heading คลาดถึง 120° ([Apple Forums 756943](https://developer.apple.com/forums/thread/756943)) และการทดสอบเก่าพบ iPhone ต่างกันเองถึง 20° ([GeoGarage/TechHive](https://blog.geogarage.com/2013/10/the-iphones-positioning-sensors-were.html)) บนหลังคาเมทัลชีทที่วางบนแป C-channel และใกล้ inverter จึงควรถือว่า compass เป็นเพียง fallback และต้องตรวจทานด้วยวิธีที่ไม่ใช้ magnetometer อย่างน้อยหนึ่งวิธี วิธีแรกคือลากเส้นตามขอบชายคาบนภาพดาวเทียม MapKit แล้วคำนวณ bearing ±90° วิธีที่สองคือเล็งดวงอาทิตย์แล้วคำนวณ azimuth ด้วย SPA วิธีที่สามคือดึงค่าจาก **Google Solar API** ซึ่งมีข้อมูลคุณภาพ BASE สำหรับไทยตั้งแต่ 2026-03-25 ต้องส่ง `requiredQuality=BASE` และ `azimuthDegrees` ของ API นี้ใช้ 0 = N ([Solar API release notes](https://developers.google.com/maps/documentation/solar/release-notes?authuser=9); [findClosest](https://developers.google.cn/maps/documentation/solar/reference/rest/v1/buildingInsights/findClosest)) วิธีสุดท้ายคือ photogrammetry จากโดรน แต่ยังไม่มีผลตรวจสอบความแม่นยำของข้อมูล BASE ในไทย และข้อกำหนดของ Google Maps Platform จำกัดการเก็บข้อมูลไว้ถาวร

### งบความไม่แน่นอน: P90 ≈ P50 × 0.90 สำหรับข้อมูลดาวเทียม และ × 0.87 สำหรับ ERA5 ล้วน

สูตรมาตรฐานคือ **P90 = P50 × (1 − 1.282·σ_total)** และ P99 ใช้ 2.326 โดย σ_total คือ RSS ของแต่ละองค์ประกอบ ส่วนความแปรปรวนระหว่างปีของค่าเฉลี่ย N ปีหารด้วย √N ([Solargis P50/P90](https://kb.solargis.com/docs/p50-p90-and-other-scenarios)) งบที่เสนอ: resource 5% (ถ้าใช้ ERA5 ที่ไม่ได้ปรับด้วยดาวเทียม ให้ใช้ 8%), transposition/thermal model 3%, loss assumptions 4%, shading 2.5% และ IAV 1 ปี 2% รวมได้ **σ ≈ 7.8% → P90 ≈ P50 × 0.90** หรือ σ ≈ 10% → × 0.87 สำหรับ ERA5 ล้วน ตัวเลขนี้สอดคล้องกับ P90 ±8% ของ Solargis สำหรับเขตร้อนชื้น IEA PVPS ก็พบว่าผู้ประเมินอิสระ 7 รายให้ค่าต่างกันด้วย SD 3.9–9.7% ([IEA PVPS T13-18](https://iea-pvps.org/wp-content/uploads/2021/01/Executive-Summary-IEA-PVPS-T13-18_2020-Uncertainties-in-Yield-Assessments-and-PV-LCOE.pdf)) ในไทย IAV เล็กเมื่อเทียบกับความไม่แน่นอนของ resource และ model จึงทำให้ P90 แบบ 1 ปีกับ 10 ปีต่างกันไม่ถึง 1% ค่าองค์ประกอบเฉพาะไทยในงบนี้เป็นค่าที่ใช้เหตุผลกำหนดขึ้น ไม่ใช่ค่าที่วัดได้

แนวปฏิบัติของ IEA PVPS T13 ในการนำเสนอคือแสดง loss chain ตั้งแต่ irradiation จนถึงพลังงานที่ส่งเข้ากริด ให้ทั้ง P50 และ P90 พร้อมระบุสมมติฐาน และทำ post-mortem เทียบกับข้อมูลวัดจริง ([IEA PVPS T13-18](https://iea-pvps.org/wp-content/uploads/2021/01/Executive-Summary-IEA-PVPS-T13-18_2020-Uncertainties-in-Yield-Assessments-and-PV-LCOE.pdf)) สำหรับเงาจากสิ่งกีดขวางใกล้ วิธี MCS แบบ sun-path ได้ผลภายใน ~10% ของ yield รายปีสำหรับระบบส่วนใหญ่ ([MCS MGD 005](https://mcscertified.com/wp-content/uploads/2025/02/MGD-005-Solar-PV-Shade-Analysis-V1.0-1.pdf)) แต่ต้องใช้ sun path ตามละติจูดไทย ซึ่งช่วง พ.ค.–ก.ค. ดวงอาทิตย์อ้อมไปทางเหนือ ข้อความ disclaimer ควรบอกว่าเป็น "ค่าประมาณเบื้องต้นจากข้อมูลรังสี [แหล่งและช่วงปี] และสมมติฐาน loss มาตรฐาน ผลผลิตปีแรก X kWh (P50) และกรณีอนุรักษ์นิยม Y kWh (P90) ผลจริงแปรผันตามสภาพอากาศ การทำความสะอาด เงา และอุปกรณ์ แบบสุดท้ายจะยืนยันด้วย PVsyst" **ห้ามนำเสนอ P50 ในฐานะตัวเลขรับประกัน** ถ้าจะรับประกัน ให้อิง P90 หรือต่ำกว่า และรับประกัน PR แบบ temperature-corrected ตาม IEC 61724-1 ยังไม่พบข้อกำหนดของ สคบ. หรือ กกพ. ว่าด้วย disclaimer ประมาณการผลผลิต

### ภาษีและค่าไฟสำหรับการแปลงเป็นเงินบาท

การแปลงเป็นเงินบาทต้องแยกพลังงานที่ใช้เองออกจากพลังงานที่ขายคืน **Savings = E_self × ค่าไฟขายปลีก (รวม Ft และ VAT) + E_export × อัตรารับซื้อ** โครงการโซลาร์ภาคประชาชนรับซื้อส่วนเกินที่ **2.20 บาท/kWh** ([ThaiPublica](https://thaipublica.org/2026/04/nepc-solar-rooftop-buyback-rate-2-20-baht/)) ร่างของ กกพ. (10 มิ.ย. 2026) กำหนดสัญญา 10 ปี ไม่เกิน 5 kW ต่อมิเตอร์ รวม 500 MW ([Thansettakij](https://www.thansettakij.com/sustainable/net-zero/661329)) แต่มีพาดหัวข่าวภายหลังระบุเป้าหมาย 10,000 MW และ 20 ปี ([InfoQuest](https://www.infoquest.co.th/?p=651060)) ซึ่งขัดกันและยังยืนยันไม่ได้ อัตราค่าไฟขายปลีก (~4+ บาท) ก็ยังไม่ได้ยืนยันในรอบนี้ ลูกค้า C&I และหน่วยงานรัฐส่วนใหญ่ไม่ได้รับเงินค่าส่งออก หรือบังคับ zero-export ส่วนเกินจึงกลายเป็น curtailment loss ค่าภาษีและค่าไฟจึงควรเก็บเป็น config ที่อัปเดตได้ ห้าม hard-code

## ข้อเสนอเชิงปฏิบัติ: API, สูตร และ data model

### การเลือก API

**Primary คือ PVGIS v5.3 `PVcalc`** เรียกจากเครื่อง (ไม่มีปัญหา CORS) หรือผ่าน backend proxy ทีละ roof face ด้วย `loss=0`, `mountingplace` ตามลักษณะการติดตั้ง, `usehorizon=1`, `userhorizon` ถ้ามีการสแกน horizon, `outputformat=json` และตั้ง timeout 15–20 วินาที retry 1–2 ครั้งพร้อม jitter เรียก `angle=0` เพิ่มอีกหนึ่งครั้งที่จุดเดียวกันเพื่อเอา H(h) = GHI ของ ERA5 **Cross-check และปรับระดับรังสีด้วย GSA `data/lta`** ซึ่งให้ GHI, GTI_opta และ PVOUT ของ Solargis ถึงปี 2025 โดยใช้ resource scaling factor k = GHI_GSA / GHI_PVGIS(angle=0) และ clamp ไว้ที่ 0.85–1.05 ถ้า k อยู่นอกช่วงหรือ GSA ใช้งานไม่ได้ ให้ใช้ k = 1 และขยาย σ_resource เป็น 8% **Fallback มีสองชั้น** ชั้นแรกคือตาราง PVGIS grid ของไทยที่คำนวณล่วงหน้าไว้ในแอป (~0.25°, ~1,000 cells × ชุด tilt/azimuth ซึ่งรันเสร็จในไม่กี่นาทีที่ 30 req/s) ใช้งานแบบ offline บนหลังคาได้ทันที ชั้นที่สองคือ PVWatts v8 `dataset=nsrdb` ที่ `developer.nlr.gov` หลังตรวจ terms แล้ว NASA POWER ใช้เป็น sanity check เท่านั้น สำหรับ hourly profile ที่ใช้คำนวณ self-consumption ให้ใช้ PVGIS `seriescalc` (ฟรี ~1 MB ต่อปี) ไม่ใช่ Open-Meteo

**เรื่อง commercial licensing** PVGIS และ GSA ใช้ได้ภายใต้เงื่อนไขอ้างอิงแหล่งที่มา ให้ใส่ "PVGIS © European Union" และ "Global Solar Atlas 2.0, Solargis/World Bank (ESMAP), CC BY 4.0" ไว้ในหน้ารายงาน แต่ **ควรส่งอีเมลยืนยันกับ ESMAP/Solargis** ก่อนเรียก GSA endpoint ในระดับ production เพราะ endpoint ไม่มีเอกสาร และ cache ผลไว้แทนการเรียกซ้ำ **Open-Meteo ให้ซื้อ Professional เฉพาะเมื่อมีความต้องการชัดเจน** เช่น ต้องใช้ time series ของ Himawari ปีล่าสุด ห้ามใช้ free tier ในแอปของบริษัท ถ้าวิศวกรใช้ Solargis หรือ Meteonorm ใน PVsyst อยู่แล้ว การซื้อ API จากผู้ให้บริการรายเดียวกันจะทำให้ตัวเลขในแอปตรงกับ PVsyst มากที่สุด ซึ่งเป็นการตัดสินใจเชิงธุรกิจในระยะถัดไป

### ลำดับสูตรคำนวณ (ต่อ roof face i)

```text
1) az_PVGIS = normalize(az_compass_N_cw − 180)  → ช่วง [−180, 180]
2) PVcalc(lat, lon, peakpower=1, loss=0, angle=β_i, aspect=az_PVGIS, mountingplace=m_i, userhorizon?)
      → E0_i = E_y (kWh/kWp, รวม AOI+spectral+thermal+DEM/user horizon แล้ว)
      → H_POA_i = H(i)_y (kWh/m²/yr), SD_i = SD_y
3) k = clamp(GHI_GSA / GHI_PVGIS(angle=0), 0.85, 1.05)          ; ไม่มี GSA → k = 1
4) H_POA_adj_i = k × H_POA_i ;  E0_adj_i = k × E0_i
5) PR_model_i = E0_i / H_POA_i                                   ; กลุ่ม A ห้ามหักซ้ำ
6) f_sys = Π(1 − loss_j) , j ∈ กลุ่ม B (ค่าเริ่มต้น ≈ 0.895)
7) f_shade_i = 1 − near-shading loss (จาก survey; ถ้าส่ง userhorizon ไปแล้ว ห้ามหักซ้ำ)
8) Yspec_i = E0_adj_i × f_sys × f_shade_i                        ; kWh/kWp/yr (P50, ปีที่ 1)
9) E_i = P_DC_i × Yspec_i ;  E_total = Σ E_i ;  P_DC = Σ P_DC_i
10) PR_i = Yspec_i / H_POA_adj_i  (ฐาน POA; ระบุว่ารวมหรือไม่รวม shading)
    PR_system = E_total / Σ(P_DC_i × H_POA_adj_i)
11) σ = √(σ_res² + σ_model² + σ_loss² + σ_shade² + (SD_y/E_y)²/N)
    P90 = P50 × (1 − 1.282σ) ; P99 = P50 × (1 − 2.326σ)
12) ปีที่ n: E_n = E_1 × (1 − 0.006)^(n−1)  (เพิ่ม LID ~1% ในปีแรกถ้าไม่ได้รวมในกลุ่ม B)
13) GHI ที่แสดงลูกค้า = GHI_GSA (ถ้ามี) ไม่เช่นนั้นใช้ GHI_PVGIS(angle=0) พร้อมบอกแหล่ง
```

ค่า `mountingplace` ให้เลือกดังนี้: ติดชิดหลังคาหรือช่องอากาศน้อยกว่า ~10 cm ใช้ `building` ยกราง ≥15 cm ใช้ `free` ช่วงระหว่างนั้นให้เรียกทั้งสองแบบแล้ว interpolate (เกณฑ์ระยะนี้เป็นการอนุมาน) ถ้าเผลอเรียก PVGIS ด้วย `loss=14` ต้องไม่คูณ f_sys ซ้ำ ทางที่ดีคือบังคับ `loss=0` ในโค้ดเสมอ เพื่อให้ loss table ของบริษัทเป็นแหล่งเดียวที่ตรวจสอบได้ ค่า P90 ใช้ σ_res = 5% เมื่อ k มาจาก GSA และ 8% เมื่อไม่มี GSA

### Data model (Swift)

```swift
enum AzimuthSource: String, Codable { case compass, mapEdge, sunSighting, googleSolar, drone, manual }
enum MountingType: String, Codable { case flush, ventilatedRack, freeStanding }   // → PVGIS building / interp / free
enum DataSource: String, Codable { case pvgisERA5, gsaSolargis, pvwattsNSRDB, nasaPower, bundledGrid, openMeteoHimawari }

struct RoofFaceInput: Codable, Identifiable {
    let id: UUID
    var label: String                      // "จั่ว-ตะวันออก"
    var tiltDeg: Double                    // 0 = แบน
    var azimuthDegTrueN: Double            // canonical: 0 = N, ตามเข็มนาฬิกา
    var azimuthSource: AzimuthSource
    var headingAccuracyDeg: Double?        // จาก CLHeading
    var magneticFieldMicroT: Double?       // |B| ใช้ตรวจการรบกวน (เทียบ ~42–45 µT)
    var azimuthCrossCheckDeltaDeg: Double? // ผลต่างกับวิธีที่ไม่ใช้ magnetometer; > 10° → flag
    var tiltMethodFlipAveraged: Bool
    var pDCkWp: Double
    var mounting: MountingType
    var nearShadingLossFrac: Double        // 0...1
    var userHorizonDeg: [Double]?          // เริ่ม N ตามเข็ม, ระยะเท่ากัน (PVGIS userhorizon)
    var pvgisAspect: Double { var a = azimuthDegTrueN - 180; if a <= -180 { a += 360 }; return a }
}

struct SiteInput: Codable {
    var latitude: Double, longitude: Double, gpsAccuracyM: Double
    var surveyedAt: Date
    var faces: [RoofFaceInput]
    var lossProfile: LossProfile
    var tariff: TariffConfig?
}

struct LossProfile: Codable {              // กลุ่ม B เท่านั้น (PVGIS คิดกลุ่ม A ให้แล้ว)
    var version: String                    // "TCRoof-TH-2026.1"
    var soiling = 0.03, lid = 0.01, mismatch = 0.01, dcWiring = 0.015
    var inverter = 0.025, acWiring = 0.005, clipping = 0.005, availability = 0.01
    var degradationPerYear = 0.006
    var factor: Double { [soiling, lid, mismatch, dcWiring, inverter, acWiring, clipping, availability]
                          .reduce(1) { $0 * (1 - $1) } }
}

struct Provenance: Codable {
    var source: DataSource
    var endpoint: String                   // "re.jrc.ec.europa.eu/api/v5_3/PVcalc"
    var radiationDB: String?               // "PVGIS-ERA5"
    var yearMin: Int?, yearMax: Int?       // 2005, 2023
    var datasetVersion: String?            // GSA "2.2.68"
    var snappedLat: Double?, snappedLon: Double?
    var requestURL: String
    var fetchedAt: Date
    var attribution: String
}

struct FaceResult: Codable {
    let faceID: UUID
    var e0kWhPerKWp: Double                // PVGIS loss=0
    var hPOAkWhm2: Double, hPOAAdjkWhm2: Double
    var lAOIPct: Double, lSpecPct: Double, lTGPct: Double   // l_spec parse จาก String
    var sdYkWhPerKWp: Double
    var specificYieldP50: Double           // kWh/kWp/yr
    var annualEnergyP50kWh: Double
    var prPOA: Double
    var prIncludesShading: Bool
    var monthlyKWh: [Double]               // 12 ค่า
}

struct Uncertainty: Codable {
    var sigmaResource: Double, sigmaModel: Double, sigmaLoss: Double, sigmaShade: Double, sigmaIAV: Double
    var sigmaTotal: Double
    var p90Factor: Double { 1 - 1.282 * sigmaTotal }
    var p99Factor: Double { 1 - 2.326 * sigmaTotal }
}

struct YieldEstimate: Codable {
    let id: UUID
    var schemaVersion: Int
    var input: SiteInput
    var ghiDisplayedkWhm2: Double, ghiSource: DataSource
    var resourceScaleK: Double             // GSA/PVGIS, clamp 0.85–1.05
    var faces: [FaceResult]
    var systemPR: Double, systemSpecificYieldP50: Double
    var annualEnergyP50kWh: Double, annualEnergyP90kWh: Double
    var uncertainty: Uncertainty
    var provenance: [Provenance]
    var crossChecks: [String: Double]      // "gsaPVOUT": 1447.9, "pvwattsNSRDB": 1400
    var warnings: [String]                 // "ERA5-only", "azimuth cross-check > 10°", ...
    var isPreliminary: Bool = true
}

struct TariffConfig: Codable {             // ห้าม hard-code; อัปเดตจาก server
    var retailTHBperKWh: Double, exportTHBperKWh: Double?  // 2.20 (ภาคประชาชน ≤5 kW)
    var selfConsumptionFrac: Double, zeroExport: Bool
    var effectiveFrom: Date, sourceNote: String
}

struct CacheKey: Hashable, Codable {       // ERA5 ~0.25° → ปัด 0.05° ไม่เสียความละเอียด
    var lat2: Int, lon2: Int               // round(lat/0.05)
    var tiltDeg: Int, aspectDeg: Int, mounting: MountingType
    var horizonHash: String?, source: DataSource, sourceVersion: String  // "v5_3/ERA5/2005-2023"
}
```

ให้ invalidate cache เมื่อ `yearMax` หรือ `datasetVersion` ใน provenance เปลี่ยน เก็บ azimuth ในรูปแบบ canonical (0 = N ตามเข็มนาฬิกา) ไว้รูปแบบเดียว แล้วแปลงเฉพาะตอน export ไป PVGIS/PVsyst (0 = S) หรือ PV*SOL `.hor` ตาม convention ของแต่ละเครื่องมือ

## Conclusion

ข้อค้นพบที่เปลี่ยนการออกแบบมากที่สุดคือ "PVGIS" ในประเทศไทยไม่ใช่ข้อมูลดาวเทียมอย่างที่คนส่วนใหญ่เข้าใจ แต่เป็น ERA5 ที่ให้ค่าสูงกว่า Solargis ราว 5% ที่กรุงเทพฯ จุดแข็งของ PVGIS ในแอปจึงอยู่ที่แบบจำลองความร้อน, AOI และ horizon ต่อ roof face ส่วนระดับรังสีควรมาจากข้อมูลดาวเทียม การแยกสองบทบาทนี้ผ่าน factor k ทำให้ได้ทั้งความเร็ว ความฟรี และความใกล้เคียงกับ PVsyst ที่ใช้ Solargis/Meteonorm ในแบบเดียวกัน ความแม่นยำของ yield ขั้นต้นในไทยถูกจำกัดด้วยสมมติฐาน loss และความเสี่ยงที่วัด azimuth ผิดหน้าหลังคา มากกว่าความแม่นของ sensor หรือการเลือกระหว่าง API งานที่คุ้มค่าที่สุดจึงเป็นการทำ loss profile แบบมีเวอร์ชันและการตรวจทาน azimuth ด้วยวิธีที่ไม่ใช้ compass ไม่ใช่การซื้อข้อมูลราคาแพง

เรื่องที่ควรทำต่อมีสามข้อ ข้อแรก เก็บ provenance และ loss profile version ของทุกประมาณการ แล้วเทียบกับผล PVsyst และข้อมูล monitoring จริงหลัง COD เพื่อปรับ k และ PR ด้วยข้อมูลของบริษัทเอง ในไทยยังไม่มีข้อมูลสาธารณะเรื่องนี้ ข้อมูลจากฝูงระบบที่ติดตั้งจริงจะกลายเป็นข้อได้เปรียบที่คู่แข่งไม่มี ข้อสอง ยืนยันเงื่อนไขการใช้งานของ PVGIS, GSA และ NLR ก่อนเปิดใช้งานจริง ข้อสาม ทบทวนอัตรา 2.20 บาท/kWh และระยะสัญญาเมื่อ กกพ. ออกระเบียบฉบับสุดท้าย
