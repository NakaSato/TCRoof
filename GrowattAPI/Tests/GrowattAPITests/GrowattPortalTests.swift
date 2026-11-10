import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import GrowattAPI

/// `GrowattPortal`: the web portal's signed-in calls (`selectPlant/getPlantList`, `log/getNewPlantFaultLog`), what
/// they send and how an answer, an expired session and a refusal read.
final class GrowattPortalTests: XCTestCase {
    override func tearDown() {
        GrowattStub.reset()
        super.tearDown()
    }

    private func portal() -> GrowattPortal {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GrowattStub.self]
        config.httpShouldSetCookies = false
        return GrowattPortal(session: URLSession(configuration: config))
    }

    private func json(_ s: String) -> Data { Data(s.utf8) }

    private func page(_ ids: [Int], page: Int, pages: Int) -> Data {
        let rows = ids.map { #"{"id":"\#($0)","plantName":"P\#($0)"}"# }.joined(separator: ",")
        return json(#"{"result":1,"obj":{"currPage":\#(page),"pages":\#(pages),"pageSize":20,"count":43,"datas":[\#(rows)]}}"#)
    }

    func testPlantListSendsThePortalsForm() async throws {
        GrowattStub.replies = [page([1782987, 9947162], page: 2, pages: 3)]
        let p = try await portal().plantList(page: 2)
        XCTAssertEqual(p.rows.map { $0["id"]?.text }, ["1782987", "9947162"])
        XCTAssertEqual(p.page, 2)
        XCTAssertEqual(p.pages, 3)
        XCTAssertEqual(p.count, 43)
        let r = try XCTUnwrap(GrowattStub.requests.first)
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.url?.absoluteString, "https://server.growatt.com/selectPlant/getPlantList")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Requested-With"), "XMLHttpRequest")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Origin"), "https://server.growatt.com")
        XCTAssertEqual(GrowattStub.bodies.first, "currPage=2&orderType=2&plantName=&plantType=-1")
    }

    func testAllPlantsReadsUntilTheLastPage() async throws {
        GrowattStub.replies = [page([1, 2], page: 1, pages: 2), page([3], page: 2, pages: 2), page([9], page: 3, pages: 2)]
        let rows = try await portal().allPlants()
        XCTAssertEqual(rows.compactMap { $0["id"]?.int }, [1, 2, 3])
        XCTAssertEqual(GrowattStub.requests.count, 2)
    }

    func testFaultLogSendsTheLogPagesForm() async throws {
        GrowattStub.replies = [json(#"{"result":1,"obj":{"pages":1,"datas":[{"deviceSn":"DYDCE9302Z","eventId":"124","eventName":"No AC Connection","occurTime":"2026-11-10 09:12:00"}]}}"#)]
        let p = try await portal().faultLog(date: "2026-11-10")
        XCTAssertEqual(p.rows.first?["eventId"]?.text, "124", "every field of a row is kept")
        XCTAssertEqual(p.pages, 1)
        XCTAssertNil(p.count)
        XCTAssertEqual(GrowattStub.requests.first?.url?.path, "/log/getNewPlantFaultLog")
        XCTAssertEqual(GrowattStub.bodies.first, "date=2026-11-10&deviceFlag=0&deviceSn=&plantId=-1&toPageNum=1&type=1")
    }

    func testTheFaultLogsPeriodsAreTheCapturedBodies() async throws {
        let empty = json(#"{"result":1,"obj":{"pages":1,"datas":[]}}"#)
        GrowattStub.replies = [empty, empty, empty]
        let p = portal()
        let zone = TimeZone(secondsFromGMT: 7 * 3600)!
        // 9 Nov 2026 20:33 on the plant's clock (GMT+7)
        let date = Date(timeIntervalSince1970: 1_794_242_000 - 3 * 3600)
        _ = try await p.faultLog(.day, of: date, timeZone: zone, plantID: "9947162")
        _ = try await p.faultLog(.month, of: date, timeZone: zone, plantID: "9947162")
        _ = try await p.faultLog(.year, of: date, timeZone: zone, plantID: "9947162")
        // byte for byte the browser's bodies (10 Nov 2026)
        XCTAssertEqual(GrowattStub.bodies, [
            "date=2026-11-09&deviceFlag=0&deviceSn=&plantId=9947162&toPageNum=1&type=1",
            "date=2026-11&deviceFlag=0&deviceSn=&plantId=9947162&toPageNum=1&type=2",
            "date=2026&deviceFlag=0&deviceSn=&plantId=9947162&toPageNum=1&type=3",
        ])
    }

    func testTheLoginPageIsSignedOut() async {
        GrowattStub.replies = [json("<!DOCTYPE html><html><head><title>Login</title></head></html>")]
        do {
            _ = try await portal().faultLog(date: "2026-11-10")
            XCTFail("the login page is no answer")
        } catch {
            XCTAssertEqual(error as? GrowattAPI.Failure, .signedOut)
        }
    }

    func testARefusalAndOtherShapes() throws {
        XCTAssertThrowsError(try GrowattPortal.parsePage(json(#"{"result":0,"msg":"no permission"}"#))) {
            XCTAssertEqual($0 as? GrowattAPI.Failure, .api(0, "no permission"))
        }
        XCTAssertThrowsError(try GrowattPortal.parsePage(json("not json"))) {
            XCTAssertEqual($0 as? GrowattAPI.Failure, .badResponse)
        }
        let list = try GrowattPortal.parsePage(json(#"{"result":1,"obj":[{"id":1},{"id":2}]}"#))
        XCTAssertEqual(list.rows.count, 2, "obj as a list is the rows")
        XCTAssertEqual(list.pages, 1, "no page count: one page")
    }

    func testCookiesFromABrowserAreSent() async throws {
        let p = portal()
        XCTAssertFalse(p.hasSession)
        let taken = p.useCookies(" mapLang=com; JSESSIONID=ABC123; assToken=0f0f; SERVERID=x|1|2; broken ")
        XCTAssertEqual(taken, ["mapLang", "JSESSIONID", "assToken", "SERVERID"], "a part without = is skipped")
        XCTAssertTrue(p.hasSession)
        GrowattStub.replies = [page([1], page: 1, pages: 1)]
        _ = try await p.plantList()
        XCTAssertEqual(GrowattStub.requests.first?.value(forHTTPHeaderField: "Cookie"),
                       "mapLang=com; JSESSIONID=ABC123; assToken=0f0f; SERVERID=x|1|2")
        p.useCookies("JSESSIONID=NEW")
        XCTAssertEqual(p.jar.header, "mapLang=com; JSESSIONID=NEW; assToken=0f0f; SERVERID=x|1|2", "a cookie set again is replaced in place")
    }

    func testMonthChartSendsThePagesForm() async throws {
        GrowattStub.replies = [json(#"{"result":1,"obj":[{"datas":{"energy":[512.3,"498.1",null]}}]}"#)]
        let lines = try await portal().monthChart(plantID: "9947162", month: "2026-11",
                                                  series: [.init(type: "max", sn: "GKLLEXC006", params: "energy")])
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].series.sn, "GKLLEXC006")
        XCTAssertEqual(lines[0].points, [512.3, 498.1, nil], "a day without a value is nil, never 0")
        XCTAssertEqual(GrowattStub.requests.first?.url?.path, "/energy/compare/getDevicesMonthChart")
        // byte for byte the browser's body
        XCTAssertEqual(GrowattStub.bodies.first,
                       "date=2026-11&jsonData=%5B%7B%22type%22%3A%22max%22%2C%22sn%22%3A%22GKLLEXC006%22%2C%22params%22%3A%22energy%22%7D%5D&plantId=9947162")
    }

    func testDayChartAndAnExpiredSession() async throws {
        GrowattStub.replies = [json(#"{"result":1,"obj":[{"datas":{"pac":[0,1500.5]}},{"datas":{"pac":[]}}]}"#),
                               json("<html><body>login</body></html>")]
        let p = portal()
        let s: [GrowattPortal.ChartSeries] = [.init(type: "plant", sn: "9947162", params: "pac"), .init(type: "max", sn: "A", params: "pac")]
        let lines = try await p.dayChart(plantID: "9947162", date: "2026-11-10", series: s)
        XCTAssertEqual(lines.map(\.series.sn), ["9947162", "A"])
        XCTAssertEqual(lines[0].points, [0, 1500.5])
        XCTAssertEqual(lines[1].points, [])
        // an inverter's power, byte for byte the browser's body (10 Nov 2026 capture)
        GrowattStub.reset()
        GrowattStub.replies = [json(#"{"result":1,"obj":[{"datas":{"pac":[null,0]}}]}"#), json("<html><body>login</body></html>")]
        let inv = try await p.dayChart(plantID: "9947162", date: "2026-11-09", series: [.init(type: "max", sn: "GKLLEXC006", params: "pac")])
        XCTAssertEqual(inv.first?.points, [nil, 0])
        XCTAssertEqual(GrowattStub.bodies.first,
                       "date=2026-11-09&jsonData=%5B%7B%22type%22%3A%22max%22%2C%22sn%22%3A%22GKLLEXC006%22%2C%22params%22%3A%22pac%22%7D%5D&plantId=9947162")
        do {
            _ = try await p.dayChart(plantID: "9947162", date: "2026-11-10", series: s)
            XCTFail("the login page is no chart")
        } catch {
            XCTAssertEqual(error as? GrowattAPI.Failure, .signedOut)
        }
    }

    func testCompareDevicesInTheLiveShape() async throws {
        // the answer's shape on 10 Nov 2026
        GrowattStub.replies = [json("""
        {"result":1,"obj":[{"devices":{"DYDCE9302Z_36":[["DYDCE9302Z_36","CHNT_THREE","1","DYDCE9302Z","DYDCE9302Z","71"]]},"deviceTypeName":"meter"},
        {"devices":{"GKLLEXC006":[["GKLLEXC006","INVERTER 2","0","DYDCE9302Z","DYDCE9302Z","4"]],"EPHNEYN00Q":[["EPHNEYN00Q","INVERTER 3","-1","DYDCE9302Z","DYDCE9302Z","0"]]},"deviceTypeName":"max"},
        {"devices":{"DYDCE9302Z_6":[["DYDCE9302Z_6","ENV_DEVICE","1","DYDCE9302Z","DYDCE9302Z","48"]]},"deviceTypeName":"env"}]}
        """)]
        let d = try await portal().compareDevices(plantID: "9947162")
        XCTAssertEqual(d.map(\.sn), ["DYDCE9302Z_36", "EPHNEYN00Q", "GKLLEXC006", "DYDCE9302Z_6"])
        XCTAssertEqual(d.map(\.type), ["meter", "max", "max", "env"])
        XCTAssertEqual(d[1].alias, "INVERTER 3")
        XCTAssertEqual(d[1].status, -1)
        XCTAssertEqual(d[0].datalogger, "DYDCE9302Z")
        XCTAssertEqual(d[2].series(.max(label: "PAC")!), .init(type: "max", sn: "GKLLEXC006", params: "pac"))
        XCTAssertEqual(GrowattStub.requests.first?.url?.path, "/energy/compare/getNewPlantDevices")
        XCTAssertEqual(GrowattStub.bodies.first, "plantId=9947162")
    }

    func testThePlantListInTheLiveShape() throws {
        // no result / obj around it, unlike the other calls
        let page = try GrowattPortal.parsePage(json("""
        {"currPage":1,"pages":3,"pageSize":20,"count":43,"ind":1,"datas":[{"eToday":"512.4","accountName":"PWA_solar","id":"9947162",
        "onlineNum":"2","plantName":"P1_33 สถานี","plantType":"0","currentPac":"61.2"}],"notPager":false,"maxCount":0}
        """))
        XCTAssertEqual(page.pages, 3)
        XCTAssertEqual(page.count, 43)
        let p = GrowattPortal.plants(in: page)
        XCTAssertEqual(p, [.init(id: "9947162", name: "P1_33 สถานี", currentPac: 61.2, eToday: 512.4, online: 2, plantType: 0, account: "PWA_solar")])
    }

    func testTheFaultLogInTheLiveShape() throws {
        let page = try GrowattPortal.parsePage(json("""
        {"result":1,"msg":null,"obj":{"pages":3,"currPage":1,"count":25,"datas":[
        {"deviceType":"MAX/MID/MAC","recoveryTime":null,"eventId":"Error 125","readFlag":"1","deviceModelName":"MAX 80KTL3 LV","plantId":"10127973",
         "eventType":"0","deviceSn":"MYHTF7F00P","recoveryStatus":"","solution":"1:Please disconnect DC and AC","eventName":"PV Isolation Low",
         "time":"2026-11-09 15:36:23","id":"1","alias":"INV 1","plantName":"P","sn":"MYHTF7F00P"},
        {"deviceType":"MAX/MID/MAC","recoveryTime":"2026-11-09 14:20:00","eventId":"Warning 203(0)","readFlag":"0","deviceModelName":"MAX 125KTL3-X LV",
         "plantId":"10127973","eventType":"1","deviceSn":"GKLQF5G047","eventName":"PV Circuit short","time":"2026-11-09 14:11:57"}]}}
        """))
        XCTAssertEqual(page.pages, 3)
        let f = GrowattPortal.faults(in: page)
        XCTAssertEqual(f.map(\.code), ["Error 125", "Warning 203(0)"])
        XCTAssertEqual(f.map(\.number), ["125", "203"])
        XCTAssertEqual(f.map(\.isWarning), [false, true])
        XCTAssertEqual(f[0].name, "PV Isolation Low")
        XCTAssertEqual(f[0].deviceModel, "MAX 80KTL3 LV")
        XCTAssertEqual(f[0].recovered, "", "still raised")
        XCTAssertEqual(f[1].recovered, "2026-11-09 14:20:00")
        XCTAssertTrue(f[0].isRead)
        XCTAssertEqual(f[0].time, "2026-11-09 15:36:23")
    }

    func testAChartAnswerNamesItsSeries() throws {
        // three devices in one call, as the live portal answered
        let lines = try GrowattPortal.parseChart(json("""
        {"result":1,"obj":[{"datas":{"pac":[0.0,96790.0]},"selfDeviceType":4,"sn":"GKLLEXC006","type":"max","params":"pac"},
        {"datas":{"positiveActiveTodayEnergy":[0.0,3489.3333]},"sn":"DYDCE9302Z_36","type":"meter","params":"positiveActiveTodayEnergy"},
        {"datas":{"radiant":[0.0,982.6667]},"sn":"DYDCE9302Z_6","type":"env","params":"radiant"}]}
        """), series: [])
        XCTAssertEqual(lines.map(\.series.type), ["max", "meter", "env"], "named by the answer, not by the order asked")
        XCTAssertEqual(lines[2].points, [0, 982.6667])
    }
}

/// The Compare page's values for a MAX inverter (the page's list, 10 Nov 2026).
final class GrowattPortalParamTests: XCTestCase {
    typealias Param = GrowattPortal.ChartParam

    func testTheMaxListInThePagesOrder() {
        let all = Param.maxInverter
        XCTAssertEqual(all.count, 1 + 1 + 3 + 10 + 10 + 32 + 3 + 10 + 32)
        XCTAssertEqual(all.prefix(6).map(\.label), ["PAC", "MPPT POWER", "R-PHASE POWER", "S-PHASE POWER", "T-PHASE POWER", "MPPT1POWER"])
        XCTAssertEqual(all.last?.label, "STRING CURRENT32")
        XCTAssertEqual(Set(all.map(\.name)).count, all.count, "every name once")
        XCTAssertEqual(Set(all.map(\.label)).count, all.count, "every label once")
    }

    func testOnlyNamesThatAnsweredAreConfirmed() {
        XCTAssertEqual(Param.maxInverter.filter(\.confirmed).map(\.name),
                       ["pac", "ppv", "pacr", "pacs", "pact", "ppv1", "vpv1", "vString1", "vString2", "vString32",
                        "vacrs", "vacs", "vact", "ipv1", "currentString1", "currentString32"], "the names that answered live")
        XCTAssertEqual(Param.meter.map(\.name), ["positiveActiveTodayEnergy", "power_factor"])
        XCTAssertTrue(Param.meter.allSatisfy(\.confirmed))
    }

    func testLookupByLabel() {
        XCTAssertEqual(Param.max(label: "STRING VOLTAGE1")?.name, "vString1")
        XCTAssertEqual(Param.max(label: "mppt3 voltage")?.name, "vpv3", "case and spaces don't matter")
        XCTAssertEqual(Param.max(label: "T-PHASE POWER")?.unit, "W")
        XCTAssertEqual(Param.max(label: "STRING CURRENT12")?.name, "currentString12")
        XCTAssertNil(Param.max(label: "STRING VOLTAGE33"))
        let s = GrowattPortal.ChartSeries(type: "max", sn: "GKLLEXC006", param: Param.max(label: "STRING VOLTAGE1")!)
        XCTAssertEqual(GrowattPortal.jsonData([s]), #"[{"type":"max","sn":"GKLLEXC006","params":"vString1"}]"#, "the captured request's jsonData")
    }

    func testAMetersLineIsTheCapturedOne() {
        let s = GrowattPortal.ChartSeries.meter(datalogger: "DYDCE9302Z", address: 36)
        XCTAssertEqual(GrowattAPI.formBody(["plantId": "9947162", "date": "2026-11-09", "jsonData": GrowattPortal.jsonData([s])]),
                       "date=2026-11-09&jsonData=%5B%7B%22type%22%3A%22meter%22%2C%22sn%22%3A%22DYDCE9302Z_36%22%2C%22params%22%3A%22positiveActiveTodayEnergy%22%7D%5D&plantId=9947162",
                       "byte for byte the browser's body (10 Nov 2026)")
        let pf = GrowattPortal.ChartSeries.meter(datalogger: "DYDCE9302Z", address: 36, param: .meterPowerFactor)
        XCTAssertEqual(GrowattPortal.jsonData([pf]), #"[{"type":"meter","sn":"DYDCE9302Z_36","params":"power_factor"}]"#)
    }

    func testAnEnvironmentSensorsLineIsTheCapturedOne() {
        let s = GrowattPortal.ChartSeries.env(datalogger: "DYDCE9302Z", address: 6)
        XCTAssertEqual(GrowattAPI.formBody(["plantId": "9947162", "date": "2026-11-09", "jsonData": GrowattPortal.jsonData([s])]),
                       "date=2026-11-09&jsonData=%5B%7B%22type%22%3A%22env%22%2C%22sn%22%3A%22DYDCE9302Z_6%22%2C%22params%22%3A%22env_temp%22%7D%5D&plantId=9947162",
                       "byte for byte the browser's body (10 Nov 2026)")
        XCTAssertEqual(GrowattPortal.ChartParam.env.map(\.name), ["env_temp", "panel_temp", "radiant", "sensorSingnalGen", "wind_angle"])
        XCTAssertEqual(GrowattPortal.jsonData([.env(datalogger: "DYDCE9302Z", address: 6, param: .windDirection)]),
                       #"[{"type":"env","sn":"DYDCE9302Z_6","params":"wind_angle"}]"#)
        XCTAssertEqual(GrowattPortal.jsonData([.env(datalogger: "DYDCE9302Z", address: 6, param: .sensorSignal)]),
                       #"[{"type":"env","sn":"DYDCE9302Z_6","params":"sensorSingnalGen"}]"#, "Growatt's spelling, as captured")
        let sun = GrowattPortal.ChartSeries.env(datalogger: "DYDCE9302Z", address: 6, param: .irradiance)
        XCTAssertEqual(GrowattPortal.jsonData([sun]), #"[{"type":"env","sn":"DYDCE9302Z_6","params":"radiant"}]"#,
                       "the irradiance's captured request")
        XCTAssertTrue(GrowattPortal.ChartParam.env.allSatisfy(\.confirmed))
        let panel = GrowattPortal.ChartSeries.env(datalogger: "DYDCE9302Z", address: 6, param: .panelTemperature)
        XCTAssertEqual(GrowattPortal.jsonData([panel]), #"[{"type":"env","sn":"DYDCE9302Z_6","params":"panel_temp"}]"#,
                       "the module temperature's captured request")
    }
}
