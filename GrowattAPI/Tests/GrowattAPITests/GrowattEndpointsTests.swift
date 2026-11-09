import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import GrowattAPI

/// The OpenAPI v1 read calls beyond what Monitoring uses, on the answers printed in the "Growatt Server API Guide"
/// (2016): what each call sends and how its answer reads.
final class GrowattEndpointsTests: XCTestCase {
    override func tearDown() {
        GrowattStub.reset()
        super.tearDown()
    }

    private func json(_ s: String) -> Data { Data(s.utf8) }

    // MARK: alarms

    private let inverterAlarms = """
    {"data":{"count":"102","sn":"YINGZHEN1","alarms":[{"alarm_code":"bit1","alarm_message":"low Current",
    "start_time":"2015-12-08T11:05:00Z","end_time":"2015-12-08T11:05:00Z","status":0},
    {"alarm_code":124,"alarm_message":"No AC Connection","start_time":"2026-11-10 09:12:00","end_time":"","status":1}]},
    "error_code":0,"error_msg":""}
    """

    func testInverterAlarms() async throws {
        GrowattStub.replies = [json(inverterAlarms)]
        let page = try await GrowattStub.api().alarms(deviceSN: "INV035C003", date: "2026-11-10", perPage: 500)
        XCTAssertEqual(page.count, 102, "a count written as text still reads")
        XCTAssertEqual(page.items, [
            .init(code: "bit1", message: "low Current", start: "2015-12-08T11:05:00Z", end: "2015-12-08T11:05:00Z", status: 0),
            .init(code: "124", message: "No AC Connection", start: "2026-11-10 09:12:00", end: "", status: 1),
        ], "a numeric code reads as its digits")
        let r = try XCTUnwrap(GrowattStub.requests.first)
        XCTAssertEqual(r.url?.path, "/v1/device/inverter/alarm")
        XCTAssertEqual(r.url?.query, "date=2026-11-10&device_sn=INV035C003&page=1&perpage=100")
        XCTAssertEqual(r.httpMethod ?? "GET", "GET")
    }

    func testStorageAlarmsArePosted() async throws {
        GrowattStub.replies = [json("""
        {"data":{"count":26,"storage_sn":"I435100018","alarms":[{"alarm_code":201,"status":1,"end_time":"2016-04-28 18:41:40.0",
        "start_time":"2016-04-28 18:41:40.0","alarm_message":"Firmware version mismatch"}]},"error_code":0,"error_msg":""}
        """)]
        let page = try await GrowattStub.api().storageAlarms(storageSN: "Y87035C003", date: "2016-01-25")
        XCTAssertEqual(page.count, 26)
        XCTAssertEqual(page.items.first?.code, "201")
        XCTAssertEqual(page.items.first?.start, "2016-04-28 18:41:40.0")
        let r = try XCTUnwrap(GrowattStub.requests.first)
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.url?.path, "/v1/device/storage/alarm_data")
        XCTAssertEqual(r.value(forHTTPHeaderField: "token"), "abc")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=UTF-8")
        XCTAssertEqual(GrowattStub.bodies.first, "date=2016-01-25&page=1&perpage=100&storage_sn=Y87035C003")
    }

    // MARK: plants

    func testPlantPageAndSearch() async throws {
        GrowattStub.replies = [json(#"{"data":{"count":1,"plants":[{"plant_id":1,"name":"P1","user_id":9,"create_date":"2026-01-02","installer":"TC"}]},"error_code":0}"#)]
        let page = try await GrowattStub.api().plantPage(search: " นครชัยศรี ")
        XCTAssertEqual(page.count, 1)
        XCTAssertEqual(page.items.first?.userID, 9)
        XCTAssertEqual(page.items.first?.installer, "TC")
        XCTAssertEqual(page.items.first?.currentPower, -1, "no power given: never reported")
        let q = try XCTUnwrap(GrowattStub.requests.first?.url?.query)
        XCTAssertTrue(q.contains("search_type=name"))
        XCTAssertTrue(q.contains("search_keyword=%E0%B8%99"), "Thai is percent-encoded: \(q)")
    }

    func testAllPlantsReadsEveryPage() async throws {
        func page(_ ids: Range<Int>, count: Int) -> Data {
            let rows = ids.map { #"{"plant_id":\#($0),"name":"P\#($0)"}"# }.joined(separator: ",")
            return json(#"{"data":{"count":\#(count),"plants":[\#(rows)]},"error_code":0}"#)
        }
        GrowattStub.replies = [page(0..<100, count: 143), page(100..<143, count: 143), page(0..<1, count: 143)]
        let all = try await GrowattStub.api().allPlants()
        XCTAssertEqual(all.count, 143)
        XCTAssertEqual(GrowattStub.requests.count, 2, "a short page is the last")
        XCTAssertEqual(GrowattStub.requests.last?.url?.query, "page=2&perpage=100")
    }

    func testUserPlantsArePosted() async throws {
        GrowattStub.replies = [json(#"{"data":{"count":1,"plants":[{"plant_id":1,"name":"Name of Plant 1","user_id":1}]},"error_code":0,"error_msg":""}"#)]
        let page = try await GrowattStub.api().userPlants(userName: "user 1")
        XCTAssertEqual(page.items.map(\.name), ["Name of Plant 1"])
        XCTAssertEqual(GrowattStub.requests.first?.httpMethod, "POST")
        XCTAssertEqual(GrowattStub.bodies.first, "page=1&perpage=100&user_name=user%201")
    }

    func testPlantDetails() async throws {
        GrowattStub.replies = [json("""
        {"data":{"locale":"en-US","name":"test_plant","user_id":1,"country":"China","latitude":"30.1","longitude":120,
        "create_date":"2015-05-03","peak_power":341.42,"currency":"RMB","timezone":"GMT+8","image_url":null,
        "arrays":[{"num_modules":1,"module_man":" Growatt "}],"inverters":[{"inverter_man":"","inverter_num":1}]},"error_code":0,"error_msg":""}
        """)]
        let d = try await GrowattStub.api().details(plantID: 2)
        XCTAssertEqual(d.name, "test_plant")
        XCTAssertEqual(d.userID, 1)
        XCTAssertEqual(d.latitude, 30.1)
        XCTAssertEqual(d.longitude, 120)
        XCTAssertEqual(d.peakPower, 341.42)
        XCTAssertEqual(d.imageURL, "", "null is empty")
        XCTAssertEqual(d.fields["arrays"]?.array?.first?["num_modules"]?.int, 1, "what isn't named is kept")
        XCTAssertEqual(GrowattStub.requests.first?.url?.query, "plant_id=2")
    }

    func testPlantDataKeepsItsExtras() throws {
        let d = try GrowattAPI.parseData(json(#"{"data":{"current_power":17.42,"today_energy":44.12,"peak_power_actual":"20","carbon_offset":1.5},"error_code":0}"#))
        XCTAssertEqual(d.peakPowerActual, 20)
        XCTAssertEqual(d.carbonOffset, 1.5)
        XCTAssertEqual(d.lastUpdate, "")
    }

    // MARK: devices

    func testDataloggers() async throws {
        GrowattStub.replies = [json("""
        {"data":{"count":2,"dataloggers":[{"sn":"601000000","type":1,"manufacturer":"igen","model":"","last_update_time":"2015-12-08T11:00:00Z"},
        {"sn":"","type":2}]},"error_code":0,"error_msg":""}
        """)]
        let page = try await GrowattStub.api().dataloggers(plantID: 2)
        XCTAssertEqual(page.count, 2)
        XCTAssertEqual(page.items, [.init(sn: "601000000", type: 1, manufacturer: "igen", lastUpdate: "2015-12-08T11:00:00Z")],
                       "a row without a serial number is skipped")
        XCTAssertEqual(GrowattStub.requests.first?.url?.path, "/v1/device/datalogger/list")
    }

    func testDevicesCarryTheirIDAndMaker() throws {
        let d = try GrowattAPI.parseDevices(json(#"{"data":{"count":1,"devices":[{"device_id":100010001,"datalogger_sn":"601000000","device_sn":"YINGZHENTEST001","type":1,"manufacturer":"igen"}]},"error_code":0}"#))
        XCTAssertEqual(d.first?.deviceID, 100010001)
        XCTAssertEqual(d.first?.manufacturer, "igen")
    }

    // MARK: inverter readings

    func testInverterHistory() async throws {
        GrowattStub.replies = [json("""
        {"data":{"datalogger_sn":"401000001","sn":"YINGZHEN1","next_page_start_id":"1000101_12313","datas":[
        {"ipv1":0.2,"vpv1":481.2,"power":185,"today_energy":24.2,"time":"2015-12-08T11:00:00Z"},
        {"ipv1":0.2,"vpv1":481.2,"power":"190","today_energy":24.3,"time":"2015-12-08T11:05:00Z"}]},"error_code":0,"error_msg":""}
        """)]
        let h = try await GrowattStub.api().inverterHistory(deviceSN: "INV035C003", start: "2015-05-05", end: "2015-05-06", perPage: 5000)
        XCTAssertEqual(h.sn, "YINGZHEN1")
        XCTAssertEqual(h.datalogger, "401000001")
        XCTAssertEqual(h.nextPageStartID, "1000101_12313")
        XCTAssertEqual(h.readings.map { $0.number("power") }, [185, 190])
        XCTAssertEqual(h.readings.last?.time, "2015-12-08T11:05:00Z")
        XCTAssertEqual(GrowattStub.requests.first?.url?.query,
                       "device_sn=INV035C003&end_date=2015-05-06&page=1&perpage=1000&start_date=2015-05-05", "at most 1000 a page")
    }

    func testLatestReadings() async throws {
        GrowattStub.replies = [json("""
        {"dataloggerSn":"AH13140003","device_sn":"2033022963","data":{"powerToday":883.8,"powerTotal":"12000","pac":1500,
        "status":3,"faultType":124,"warnCode":0,"time":"2016-06-16 19:24:46","vString3":612.5,"bigDevice":false}}
        """)]
        let l = try await GrowattStub.api().latest(deviceSN: "2033022963")
        XCTAssertEqual(l.sn, "2033022963")
        XCTAssertEqual(l.datalogger, "AH13140003")
        XCTAssertEqual(l.status, 3)
        XCTAssertEqual(l.power, 1500)
        XCTAssertEqual(l.energyToday, 883.8)
        XCTAssertEqual(l.energyTotal, 12000)
        XCTAssertEqual(l.faultType, 124)
        XCTAssertEqual(l.warnCode, 0)
        XCTAssertEqual(l.time, "2016-06-16 19:24:46")
        XCTAssertEqual(l.readings.number("vString3"), 612.5)
        XCTAssertEqual(l.readings["bigDevice"], .bool(false))
    }

    func testBatchLatestReadings() async throws {
        GrowattStub.replies = [json("""
        {"inverters":["2033022963","TL15300005"],"data":{
        "2033022963":{"dataloggerSn":"AH13140003","2033022963":{"powerToday":883.8,"status":1}},
        "TL15300005":{"dataloggerSn":"AH2","TL15300005":{"powerToday":10,"status":3}}},"error_code":0}
        """)]
        let l = try await GrowattStub.api().latest(deviceSNs: ["2033022963", "TL15300005"])
        XCTAssertEqual(l["2033022963"]?.energyToday, 883.8)
        XCTAssertEqual(l["2033022963"]?.datalogger, "AH13140003")
        XCTAssertEqual(l["TL15300005"]?.status, 3)
        XCTAssertEqual(GrowattStub.requests.first?.httpMethod, "POST")
        XCTAssertEqual(GrowattStub.bodies.first, "inverters=%5B%222033022963%22%2C%22TL15300005%22%5D&pageNum=1")
    }

    /// The string and MPPT currents by the names the live portal answered for a MAX (`currentString1…`, `ipv1…`; not
    /// yet seen in an OpenAPI answer): numbers or text, up to the last one sent, a gap nil, none sent empty.
    func testStringAndMPPTCurrents() throws {
        let l = try GrowattAPI.parseLatestBatch(json(#"""
        {"data":{"MAX1":{"dataloggerSn":"DL","MAX1":{"currentString1":9.8,"currentString2":"9.6","currentString4":0,
        "ipv1":19.4,"ipv2":"0","pac":120000}},"MAX2":{"dataloggerSn":"DL","MAX2":{"pac":0}}},"error_code":0}
        """#))
        XCTAssertEqual(l["MAX1"]?.stringCurrents, [9.8, 9.6, nil, 0])
        XCTAssertEqual(l["MAX1"]?.mpptCurrents, [19.4, 0])
        XCTAssertEqual(l["MAX2"]?.stringCurrents, [])
        XCTAssertEqual(l["MAX2"]?.mpptCurrents, [])
    }

    func testInverterInfo() async throws {
        GrowattStub.replies = [json(#"{"device_sn":"2033022963","dataloggerSn":"GT25290025","data":{"model":33079,"fwVersion":"G.2.0","lost":true,"nominalPower":2870},"error_code":0}"#)]
        let i = try await GrowattStub.api().info(deviceSN: "2033022963")
        XCTAssertEqual(i.text("fwVersion"), "G.2.0")
        XCTAssertEqual(i.number("nominalPower"), 2870)
        XCTAssertEqual(i["lost"]?.bool, true)
        XCTAssertEqual(GrowattStub.requests.first?.url?.path, "/v1/device/inverter/inv_data_info")
    }

    func testStorageReadingsArePosted() async throws {
        GrowattStub.replies = [
            json(#"{"device_sn":"I435100018","dataloggerSn":"YU34130371","data":{"eDischargeToday":0.2,"capacity":"87","status":1}}"#),
            json(#"{"data":{"storage_sn":"I435100018","next_page_start_id":3,"datas":[{"capacity":80,"time":"2015-05-05 10:00:00"}]},"error_code":0}"#),
        ]
        let a = GrowattStub.api()
        let l = try await a.storageLatest(storageSN: "Y873140005")
        XCTAssertEqual(l.sn, "I435100018")
        XCTAssertEqual(l.readings.number("capacity"), 87)
        let h = try await a.storageHistory(storageSN: "Y873140005", start: "2015-05-05", end: "2015-05-06")
        XCTAssertEqual(h.sn, "I435100018")
        XCTAssertEqual(h.nextPageStartID, "3")
        XCTAssertEqual(h.readings.first?.number("capacity"), 80)
        XCTAssertEqual(GrowattStub.requests.map(\.httpMethod), ["POST", "POST"])
        XCTAssertEqual(GrowattStub.bodies.first, "storage_sn=Y873140005")
    }

    // MARK: users

    func testEndUsers() async throws {
        GrowattStub.replies = [json("""
        {"data":{"count":4,"c_user":[{"c_user_email":"770988255@qq.com","c_user_id":"8","c_user_name":"tt",
        "c_user_regtime":"2016-02-25","c_user_tel":"13875214562"}]},"error_code":0,"error_msg":""}
        """)]
        let page = try await GrowattStub.api().endUsers(perPage: 10)
        XCTAssertEqual(page.count, 4)
        XCTAssertEqual(page.items, [.init(id: 8, email: "770988255@qq.com", name: "tt", phone: "13875214562", registered: "2016-02-25")])
        XCTAssertEqual(GrowattStub.requests.first?.url?.query, "page=1&perpage=10")
    }

    // MARK: failures and values

    func testAFailureOnAPostedCall() async {
        GrowattStub.replies = [json(#"{"error_code":10005,"error_msg":"storage not exist","data":""}"#)]
        do {
            _ = try await GrowattStub.api().storageLatest(storageSN: "x")
            XCTFail("10005 is a failure")
        } catch {
            XCTAssertEqual(error as? GrowattAPI.Failure, .api(10005, "storage not exist"))
        }
        XCTAssertThrowsError(try GrowattAPI.parseAlarms(json(#"{"data":{"count":0},"error_code":0}"#))) {
            XCTAssertEqual($0 as? GrowattAPI.Failure, .badResponse, "no alarms list")
        }
    }

    func testJSONValues() throws {
        let v = try JSONDecoder().decode(JSONValue.self, from: json(#"{"a":"1.50","b":2,"c":true,"d":null,"e":[1],"f":"x","g":0}"#))
        XCTAssertEqual(v["a"]?.number, 1.5)
        XCTAssertEqual(v["b"]?.text, "2")
        XCTAssertEqual(v["b"]?.int, 2)
        XCTAssertEqual(v["a"]?.int, nil, "1.5 isn't whole")
        XCTAssertEqual(v["c"], .bool(true))
        XCTAssertEqual(v["d"], .null)
        XCTAssertNil(v["d"]?.text)
        XCTAssertEqual(v["e"]?.array, [.number(1)])
        XCTAssertNil(v["f"]?.number)
        XCTAssertEqual(v["g"]?.bool, false)
        XCTAssertNil(v["missing"])
    }
}
