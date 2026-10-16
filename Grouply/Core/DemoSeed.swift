import Foundation

extension DemoStore {
  func loadSeed() {
    func day(_ offset: Int) -> Date {
      Calendar.current.date(
        byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))!
        .addingTimeInterval(23 * 3600 + 59 * 60)
    }
    users = [
      GLUser(id: "u1", name: "Alex", email: "alex.pratama@student.ac.id", tint: "#DED2FF"),
      GLUser(id: "u2", name: "Raka", email: "raka.aditya@student.ac.id", tint: "#C9F2D6"),
      GLUser(id: "u3", name: "Nadia", email: "nadia.putri@student.ac.id", tint: "#F9E9BE"),
      GLUser(id: "u4", name: "Dimas", email: "dimas.s@student.ac.id", tint: "#D8EAF4"),
      GLUser(id: "u5", name: "Sinta", email: "sinta@student.ac.id", tint: "#F6CED1"),
      GLUser(id: "u6", name: "Bima", email: "bima@student.ac.id", tint: "#C9F2D6"),
      GLUser(id: "u7", name: "Laras", email: "laras@student.ac.id", tint: "#D8EAF4"),
    ]
    groups = [
      GLGroup(
        id: "g3", name: "Statistika · Kelompok 1",
        description: "Analisis data survei kebiasaan belajar.", course: "Statistika Dasar",
        memberIDs: ["u6", "u7"], coordinatorID: "u6", tint: "#D8EAF4", icon: "chart.bar.fill"),
      GLGroup(
        id: "g1", name: "Basis Data · Kelompok 3",
        description: "Tugas besar Basis Data semester 3.", course: "Basis Data · IF-B",
        memberIDs: ["u1", "u2", "u3", "u4", "u5"], coordinatorID: "u1", tint: "#C9F2D6",
        icon: "externaldrive.fill"),
      GLGroup(
        id: "g2", name: "UI/UX Research", description: "Riset usability aplikasi kampus.",
        course: "Interaksi Manusia & Komputer", memberIDs: ["u1", "u3", "u5"], coordinatorID: "u3",
        tint: "#DED2FF", icon: "sparkles"),
    ]
    projects = [
      GLProject(
        id: "p1", groupID: "g1", title: "Sistem Informasi Perpustakaan",
        description:
          "Rancang basis data perpustakaan kampus: ERD, normalisasi sampai 3NF, DDL, dan presentasi akhir.",
        dueAt: day(8), status: .active),
      GLProject(
        id: "p3", groupID: "g1", title: "Proposal Topik",
        description: "Proposal topik tugas besar untuk disetujui dosen.", dueAt: day(-7),
        status: .completed),
      GLProject(
        id: "p2", groupID: "g2", title: "Laporan Usability Test",
        description: "Uji 5 partisipan pada aplikasi KRS online dan susun laporan temuan.",
        dueAt: day(14), status: .active),
    ]
    tasks = [
      GLTask(
        id: "t1", projectID: "p1", title: "Draft diagram ERD",
        description: "ERD lengkap dengan entity Member, Book, Loan, Fine beserta kardinalitasnya.",
        assigneeID: "u2", reviewerID: "u1", dueAt: day(2), status: .inReview),
      GLTask(
        id: "t2", projectID: "p1", title: "Normalisasi tabel ke 3NF",
        description:
          "Turunkan ERD ke tabel relasional dan normalisasi sampai 3NF. Tulis alasan setiap dekomposisi.",
        assigneeID: "u1", reviewerID: "u3", dueAt: day(1), status: .inProgress),
      GLTask(
        id: "t3", projectID: "p1", title: "Tulis script DDL SQL",
        description: "Script CREATE TABLE untuk PostgreSQL, lengkap dengan constraint dan index.",
        assigneeID: "u1", reviewerID: "u4", dueAt: day(3), status: .needsRevision),
      GLTask(
        id: "t11", projectID: "p1", title: "Kamus data",
        description: "Dokumentasikan setiap atribut: tipe data, panjang, dan contoh nilai.",
        assigneeID: "u2", reviewerID: "u3", dueAt: day(4), status: .todo),
      GLTask(
        id: "t4", projectID: "p1", title: "Studi literatur",
        description: "Rangkum 5 referensi sistem perpustakaan.", assigneeID: "u3", reviewerID: "u2",
        dueAt: day(-4), status: .done),
      GLTask(
        id: "t5", projectID: "p1", title: "Slide presentasi",
        description: "10 slide untuk presentasi 15 menit di kelas.", assigneeID: "u4",
        reviewerID: "u1", dueAt: day(6), status: .todo),
      GLTask(
        id: "t6", projectID: "p1", title: "Narasi use case",
        description: "Narasi use case peminjaman dan pengembalian buku.", assigneeID: "u5",
        reviewerID: "u3", dueAt: day(-3), status: .done),
      GLTask(
        id: "t12", projectID: "p3", title: "Draft proposal",
        description: "Latar belakang, rumusan masalah, dan ruang lingkup.", assigneeID: "u5",
        reviewerID: "u1", dueAt: day(-10), status: .done),
      GLTask(
        id: "t13", projectID: "p3", title: "Revisi proposal",
        description: "Perbaiki sesuai masukan dosen.", assigneeID: "u2", reviewerID: "u3",
        dueAt: day(-7), status: .done),
      GLTask(
        id: "t7", projectID: "p2", title: "Rekrut 5 partisipan",
        description: "Rekrut mahasiswa angkatan 2024–2025.", assigneeID: "u5", reviewerID: "u1",
        dueAt: day(-2), status: .done),
      GLTask(
        id: "t8", projectID: "p2", title: "Script wawancara",
        description: "Script wawancara 20 menit dan 6 skenario tugas.", assigneeID: "u1",
        reviewerID: "u5", dueAt: day(-1), status: .todo),
      GLTask(
        id: "t9", projectID: "p2", title: "Affinity mapping",
        description: "Kelompokkan temuan dari 5 sesi wawancara.", assigneeID: "u3",
        reviewerID: "u5", dueAt: day(9), status: .inProgress),
      GLTask(
        id: "t10", projectID: "p2", title: "Ringkasan temuan sesi 1",
        description: "Rangkum 5 temuan utama dari sesi 1, lengkap dengan kutipan partisipan.",
        assigneeID: "u1", reviewerID: "u3", dueAt: day(5), status: .todo),
    ]
    tasks[tasks.firstIndex { $0.id == "t1" }!].submissions = [
      GLSubmission(
        revision: 1, authorID: "u2",
        note: "ERD v1 dengan 9 entity. Tolong cek apakah Fine perlu jadi entity sendiri.",
        links: ["https://drive.google.com/file/d/erd-v1"],
        createdAt: day(-2).addingTimeInterval(-8 * 3600))
    ]
    tasks[tasks.firstIndex { $0.id == "t3" }!].submissions = [
      GLSubmission(
        revision: 1, authorID: "u1", note: "DDL v1, 9 tabel dengan primary key.",
        links: ["https://github.com/kelompok3/perpus-ddl"], createdAt: day(-1),
        decision: "changes_requested",
        feedback:
          "Tambahkan ON DELETE untuk FK di tabel Loan dan CHECK tanggal kembali ≥ tanggal pinjam.",
        reviewerID: "u4")
    ]
    for i in tasks.indices where tasks[i].status == .done {
      tasks[i].submissions = [
        GLSubmission(
          revision: 1, authorID: tasks[i].assigneeID,
          note: "Hasil pekerjaan selesai dan sudah disetujui.", links: [],
          createdAt: tasks[i].dueAt.addingTimeInterval(-86400), decision: "approved",
          reviewerID: tasks[i].reviewerID)
      ]
    }
    messages = [
      GLMessage(
        groupID: "g1", taskID: nil, senderID: "u3",
        text: "Guys, deadline ERD hari Minggu ya. Jangan mepet.",
        createdAt: day(-1).addingTimeInterval(-4 * 3600)),
      GLMessage(
        groupID: "g1", taskID: nil, senderID: "u2", text: "Siap, aku lanjut ERD malam ini.",
        createdAt: day(-1).addingTimeInterval(-3 * 3600)),
      GLMessage(
        groupID: "g1", taskID: nil, senderID: "u4",
        text: "Lex, cek feedback-ku di tugas DDL ya. Minor kok.",
        createdAt: day(0).addingTimeInterval(-15 * 3600)),
      GLMessage(
        groupID: "g1", taskID: nil, senderID: "u1", text: "Oke, nanti malam aku benerin.",
        createdAt: day(0).addingTimeInterval(-14 * 3600)),
      GLMessage(
        groupID: "g2", taskID: nil, senderID: "u3",
        text: "Alex, script wawancara jangan lupa ya, sesi 2 hari Senin.",
        createdAt: day(0).addingTimeInterval(-13 * 3600)),
      GLMessage(
        groupID: "g3", taskID: nil, senderID: "u7",
        text: "Halo! Nanti kita bagi tugas analisis ya.", createdAt: day(-1)),
      GLMessage(
        groupID: "g1", taskID: "t1", senderID: "u3",
        text: "Fine mending jadi entity sendiri, biar denda per hari gampang dihitung.",
        createdAt: day(-2)),
      GLMessage(
        groupID: "g1", taskID: "t1", senderID: "u2",
        text: "Udah aku kirim ya, tinggal nunggu review.", createdAt: day(-1)),
      GLMessage(
        groupID: "g1", taskID: "t2", senderID: "u3",
        text: "Sertakan tabel sebelum dan sesudah normalisasi ya.", createdAt: day(-1)),
      GLMessage(
        groupID: "g1", taskID: "t3", senderID: "u4",
        text: "Sisanya udah oke, tinggal constraint aja.",
        createdAt: day(0).addingTimeInterval(-15 * 3600)),
    ]
    // Demo history must precede the wall clock so new local messages become unread immediately.
    for i in messages.indices {
      messages[i].createdAt = Date().addingTimeInterval(Double(i - messages.count) * 3600)
    }
    invites = [
      GLInvite(id: "i1", groupID: "g3", code: "STAT-K1Q", createdAt: day(-1), expiresAt: day(6)),
      GLInvite(id: "i2", groupID: "g1", code: "BD3-7KQ2", createdAt: day(-2), expiresAt: day(5)),
      GLInvite(
        id: "i3", groupID: "g1", code: "BD3-USED", createdAt: day(-6), expiresAt: day(1),
        useCount: 1),
      GLInvite(id: "i4", groupID: "g2", code: "UIX-OLD1", createdAt: day(-15), expiresAt: day(-8)),
      GLInvite(
        id: "i5", groupID: "g1", code: "BD3-OFF9", createdAt: day(-3), expiresAt: day(4),
        revoked: true),
    ]
    currentUserID = nil
  }
}
