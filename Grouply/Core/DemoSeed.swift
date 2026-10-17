import Foundation

extension DemoStore {
  func loadSeed() {
    // Demo clock: the prototype's "Jum, 16 Okt 19:30" mapped onto today.
    func at(_ offset: Int, _ h: Int, _ m: Int) -> Date {
      Calendar.current.date(
        byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))!
        .addingTimeInterval(Double(h * 3600 + m * 60))
    }
    func day(_ offset: Int) -> Date { at(offset, 23, 59) }
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
        memberIDs: ["u6", "u7"], coordinatorID: "u6", tint: "#D8EAF4", icon: "chart.xyaxis.line"),
      GLGroup(
        id: "g1", name: "Basis Data · Kelompok 3",
        description: "Tugas besar Basis Data semester 3.", course: "Basis Data · IF-B",
        memberIDs: ["u1", "u2", "u3", "u4", "u5"], coordinatorID: "u1", tint: "#C9F2D6",
        icon: "cylinder.split.1x2"),
      GLGroup(
        id: "g2", name: "UI/UX Research", description: "Riset usability aplikasi kampus.",
        course: "Interaksi Manusia & Komputer", memberIDs: ["u1", "u3", "u5"], coordinatorID: "u3",
        tint: "#DED2FF", icon: "circle.grid.2x2"),
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
        assigneeID: "u1", reviewerID: "u4", dueAt: at(3, 12, 0), status: .needsRevision),
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
        note:
          "ERD v1 dengan 9 entity. Relasi Member–Loan 1:N. Tolong cek apakah Fine perlu jadi entity sendiri.",
        links: ["https://drive.google.com/file/d/erd-v1"], createdAt: at(-2, 15, 20))
    ]
    tasks[tasks.firstIndex { $0.id == "t3" }!].submissions = [
      GLSubmission(
        revision: 1, authorID: "u1", note: "DDL v1, 9 tabel dengan primary key.",
        links: ["https://github.com/kelompok3/perpus-ddl"], createdAt: at(-1, 21, 5),
        decision: "changes_requested",
        feedback:
          "Tambahkan ON DELETE untuk FK di tabel Loan, dan CHECK tanggal kembali ≥ tanggal pinjam.",
        reviewerID: "u4")
    ]
    let approved: [String: (String, Date)] = [
      "t4": ("Rangkuman 5 jurnal.", at(-5, 12, 0)), "t6": ("Narasi 4 use case.", at(-3, 12, 0)),
      "t12": ("Draft 4 halaman.", at(-11, 12, 0)), "t13": ("Sudah sesuai masukan.", at(-7, 12, 0)),
      "t7": ("5 partisipan sudah terjadwal.", at(-3, 12, 0)),
    ]
    for i in tasks.indices where tasks[i].status == .done {
      let (note, date) = approved[tasks[i].id] ?? ("Hasil pekerjaan selesai.", tasks[i].dueAt)
      tasks[i].submissions = [
        GLSubmission(
          revision: 1, authorID: tasks[i].assigneeID, note: note, links: [], createdAt: date,
          decision: "approved", reviewerID: tasks[i].reviewerID)
      ]
    }
    func msg(
      _ g: String, _ task: String?, _ from: String, _ text: String, _ date: Date,
      _ kind: String = "text", _ target: String? = nil
    ) -> GLMessage {
      GLMessage(
        groupID: g, taskID: task, senderID: from, text: text, createdAt: date, kind: kind,
        targetTaskID: target)
    }
    messages = [
      msg("g1", nil, "u2", "mengirim hasil", at(-2, 15, 20), "activity", "t1"),
      msg("g1", nil, "u3", "Guys, deadline ERD hari Minggu ya. Jangan mepet.", at(-1, 19, 40)),
      msg("g1", nil, "u2", "Siap, aku lanjut ERD malam ini.", at(-1, 20, 14)),
      msg("g1", nil, "u1", "mengirim hasil", at(-1, 21, 5), "activity", "t3"),
      msg("g1", nil, "u4", "meminta revisi", at(0, 8, 40), "activity", "t3"),
      msg("g1", nil, "u4", "Lex, cek feedback-ku di tugas DDL ya. Minor kok.", at(0, 8, 42)),
      msg("g1", nil, "u1", "Oke, nanti malam aku benerin.", at(0, 9, 15)),
      msg(
        "g1", nil, "u5", "Template slide aku taruh sini: https://canva.com/design/perpus-k3",
        at(0, 12, 10)),
      msg("g1", nil, "u2", "ERD-ku udah 2 hari nunggu review nih", at(0, 18, 55)),
      msg("g1", nil, "u3", "Nanti malam call bentar bisa? 15 menit aja.", at(0, 19, 2)),
      msg("g2", nil, "u1", "menyetujui", at(-3, 16, 0), "activity", "t7"),
      msg("g2", nil, "u5", "Makasih Alex! Jadwal sesi aku share besok.", at(-3, 16, 4)),
      msg("g2", nil, "u3", "Sesi 1 lancar. Catatan lengkap: https://notion.so/sesi-1-krs", at(0, 10, 20)),
      msg("g2", nil, "u3", "Alex, script wawancara jangan lupa ya, sesi 2 hari Senin.", at(0, 10, 21)),
      msg("g3", nil, "u6", "membuat grup", at(-1, 9, 0), "system"),
      msg("g3", nil, "u7", "Halo! Nanti kita bagi tugas analisis ya.", at(-1, 9, 12)),
      msg(
        "g1", "t1", "u3", "Fine mending jadi entity sendiri, biar denda per hari gampang dihitung.",
        at(-2, 13, 2)),
      msg("g1", "t1", "u2", "mengirim revisi 1", at(-2, 15, 20), "system", "t1"),
      msg("g1", "t1", "u2", "Udah aku kirim ya, tinggal nunggu review.", at(-2, 15, 21)),
      msg("g1", "t2", "u3", "Sertakan tabel sebelum dan sesudah normalisasi ya.", at(-1, 10, 14)),
      msg("g1", "t3", "u1", "mengirim revisi 1", at(-1, 21, 5), "system", "t3"),
      msg("g1", "t3", "u4", "meminta revisi", at(0, 8, 40), "system", "t3"),
      msg("g1", "t3", "u4", "Sisanya udah oke, tinggal constraint aja.", at(0, 8, 41)),
    ]
    // Seed history must precede the wall clock so new local messages sort after it.
    if let latest = messages.map(\.createdAt).max(), latest > Date() {
      let shift = Date().addingTimeInterval(-60).timeIntervalSince(latest)
      for i in messages.indices { messages[i].createdAt.addTimeInterval(shift) }
    }
    // Unread counts from the prototype: everything else in the group chat is already read.
    readMessageIDs = [:]
    for (key, unread) in ["u1:g1": 2, "u2:g1": 1, "u3:g1": 0, "u4:g1": 3, "u5:g1": 0,
      "u1:g2": 0, "u3:g2": 1, "u5:g2": 0, "u6:g3": 0, "u7:g3": 0]
    {
      let parts = key.split(separator: ":").map(String.init)
      let thread = messages.filter { $0.groupID == parts[1] && $0.taskID == nil }
      let fromOthers = thread.filter { $0.senderID != parts[0] }.map(\.id)
      let unreadIDs = Set(fromOthers.suffix(unread))
      readMessageIDs[key] = Set(thread.map(\.id)).subtracting(unreadIDs)
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
