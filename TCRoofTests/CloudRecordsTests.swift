import XCTest
@testable import TCRoof
import TCRoofCore

final class CloudRecordsTests: XCTestCase {
    func testJobRecordRoundtripJSON() throws {
        let record = Job.Record(
            code: "PWA-101",
            projectName: "สถานีผลิตน้ำสำนักงาน",
            customerName: "กปภ. สาขาภูเก็ต",
            phone: "076-123456",
            address: "123 ถ.เทพกระษัตรี",
            province: "ภูเก็ต",
            capacityKW: 127.68,
            team: "ทีม 1",
            status: "ติดตั้งแล้ว",
            surveyDate: 1730000000000,
            installStart: 1730100000000,
            createdAt: 1729000000000,
            installDays: 45,
            driveFolderURL: "https://drive.google.com/drive/folders/test1234",
            mpNumber: 101,
            inverterKW: 110.0,
            scheduleInput: "{\"test\":true}",
            scheduleActual: "{\"actual\":true}",
            scheduleWorkbookDriveID: "drive_file_123",
            scheduleWorkbookName: "plan_101.xlsx",
            routineSettings: "{\"settings\":true}",
            weeklyRequests: "[{\"week\":1}]",
            weeklyRequestsBy: "contractor@test.com",
            stationDocs: "{\"docs\":true}",
            weeklySent: "[{\"sent\":1}]",
            drawings: "[]",
            scheduleWBS: "[{\"id\":\"wbs-1\"}]",
            wbsTicks: "{\"wbs-1\":{\"done\":true}}",
            wbsTicksBy: "wit.chanthawat@gmail.com",
            kind: "pwa",
            iecReport: "{\"iec\":true}",
            iecState: "closed",
            externals: ["enwuft@gmail.com"],
            supervisor: "wit.chanthawat@gmail.com",
            teamMembers: ["wit.chantawat@gmail.com"],
            latitude: 7.9812,
            longitude: 98.3621
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(record)
        let decoded = try JSONDecoder().decode(Job.Record.self, from: data)

        XCTAssertEqual(record, decoded)
        XCTAssertTrue(decoded.hasPWAData)
        XCTAssertEqual(decoded.code, "PWA-101")
        XCTAssertEqual(decoded.latitude, 7.9812)
        XCTAssertEqual(decoded.longitude, 98.3621)
        XCTAssertEqual(decoded.externals, ["enwuft@gmail.com"])
        XCTAssertEqual(decoded.teamMembers, ["wit.chantawat@gmail.com"])
    }

    func testJobApplyRecordUpdatesFields() {
        let job = Job(
            code: "OLD-CODE",
            projectName: "Old Project",
            customerName: "Old Customer",
            province: "เชียงใหม่",
            capacityKW: 50.0,
            team: .t1,
            status: .interested,
            surveyDate: .now,
            installStart: .now,
            installDays: 30
        )

        let record = Job.Record(
            code: "PWA-999",
            projectName: "สถานีจ่ายน้ำใหม่",
            customerName: "การประปาส่วนภูมิภาค",
            phone: "081-9998888",
            address: "456 ถ.มิตรภาพ",
            province: "ขอนแก่น",
            capacityKW: 250.0,
            team: "ทีม 2",
            status: "กำลังติดตั้ง",
            surveyDate: 1730000000000,
            installStart: 1730100000000,
            createdAt: 1729000000000,
            installDays: 60,
            driveFolderURL: "https://drive.google.com/test",
            mpNumber: 999,
            inverterKW: 220.0,
            scheduleInput: "{\"input\":1}",
            scheduleActual: "{\"actual\":1}",
            scheduleWorkbookDriveID: "wb_id_999",
            scheduleWorkbookName: "plan_999.xlsx",
            routineSettings: nil,
            weeklyRequests: nil,
            weeklyRequestsBy: nil,
            stationDocs: nil,
            weeklySent: nil,
            drawings: nil,
            scheduleWBS: nil,
            wbsTicks: nil,
            wbsTicksBy: nil,
            kind: "pwa",
            iecReport: nil,
            iecState: nil,
            externals: ["contractor@test.com"],
            supervisor: "wit.chanthawat@gmail.com",
            teamMembers: ["eng1@test.com", "eng2@test.com"],
            latitude: 16.4322,
            longitude: 102.8236
        )

        let applied = job.apply(record, jobs: [:])
        XCTAssertTrue(applied)
        XCTAssertEqual(job.code, "PWA-999")
        XCTAssertEqual(job.projectName, "สถานีจ่ายน้ำใหม่")
        XCTAssertEqual(job.province, "ขอนแก่น")
        XCTAssertEqual(job.capacityKW, 250.0)
        XCTAssertEqual(job.mpNumber, 999)
        XCTAssertEqual(job.inverterKW, 220.0)
        XCTAssertEqual(job.supervisorEmail, "wit.chanthawat@gmail.com")
        XCTAssertEqual(job.externals, ["contractor@test.com"])
        XCTAssertEqual(job.teamMembers, ["eng1@test.com", "eng2@test.com"])
        XCTAssertEqual(job.latitude, 16.4322)
        XCTAssertEqual(job.longitude, 102.8236)
    }

    func testSurveyFormRecordRoundtripJSON() throws {
        let record = SurveyForm.Record(
            createdAt: 1730000000000,
            surveyor: "วิศวกร ทดสอบ",
            roofType: "metal_sheet",
            orientation: "south",
            shading: "none",
            meterPhase: "3_phase",
            notes: "หลังคาแข็งแรงดี",
            roofAreaSqm: 450.0,
            monthlyBill: 45000.0,
            recommendedKW: 30.0,
            tiltDegree: 12,
            mainBreakerAmp: 100,
            structureOK: true,
            jobID: "PWA-101",
            isDraft: false,
            utility: "PEA",
            caNumber: "020012345678",
            meterSize: "30(100)",
            tariff: "2.1.2",
            grounding: "copper_rod"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoded = try JSONDecoder().decode(SurveyForm.Record.self, from: data)

        XCTAssertEqual(record, decoded)
        XCTAssertEqual(decoded.surveyor, "วิศวกร ทดสอบ")
        XCTAssertEqual(decoded.jobID, "PWA-101")
        XCTAssertEqual(decoded.structureOK, true)
    }

    func testInstallLogRecordRoundtripJSON() throws {
        let record = InstallLog.Record(
            date: 1730000000000,
            createdAt: 1730001000000,
            recorder: "wit.chanthawat@gmail.com",
            details: "ติดตั้งโครงสร้างแผงโซลาร์เซลล์ หลังคา 1 และ 2 เสร็จเรียบร้อย",
            jobID: "PWA-101",
            report: "{\"progress\":100}",
            engineerSignedAt: 1730002000000,
            inspectorAckAt: 1730003000000,
            externals: ["enwuft@gmail.com"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoded = try JSONDecoder().decode(InstallLog.Record.self, from: data)

        XCTAssertEqual(record, decoded)
        XCTAssertEqual(decoded.recorder, "wit.chanthawat@gmail.com")
        XCTAssertEqual(decoded.details, "ติดตั้งโครงสร้างแผงโซลาร์เซลล์ หลังคา 1 และ 2 เสร็จเรียบร้อย")
        XCTAssertEqual(decoded.jobID, "PWA-101")
        XCTAssertEqual(decoded.report, "{\"progress\":100}")
        XCTAssertEqual(decoded.externals, ["enwuft@gmail.com"])
    }
}
