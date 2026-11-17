import AtolyeCore
import SwiftUI

/// Kişisel GitHub panosu: katkı grafiği, sayılar, son 30 günün depoları.
struct GitHubWindow: View {
    let github: GitHubModel

    var body: some View {
        Group {
            switch github.phase {
            case .signedOut: signIn
            case let .waiting(code): waiting(code)
            case .signedIn: dashboard
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(GHTheme.background)
        .foregroundStyle(GHTheme.text)
        .onAppear { github.refreshIfStale() }
    }

    // MARK: Giriş

    private var signIn: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 40)).foregroundStyle(GHTheme.green(3))
            Text(L("GitHub ile giriş yap")).font(.title2.bold())
            Text(L("Katkı grafiğini, serini ve son dönemde çalıştığın depoları burada görürsün.") + "\n"
                 + L("Agent Workshop yalnızca okur; hiçbir şey yazmaz. Anahtar bu Mac'in Anahtar Zinciri'nde durur."))
                .multilineTextAlignment(.center).foregroundStyle(GHTheme.muted).frame(maxWidth: 440)
            if github.configured {
                Button { github.signIn() } label: {
                    Text(L("GitHub ile giriş yap")).padding(.horizontal, 14).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).tint(GHTheme.green(4))
            }
            if !github.configured, github.ghPath != nil {
                Button { github.useGHLogin() } label: {
                    Text(L("Bu Mac'teki GitHub girişini kullan")).padding(.horizontal, 14).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).tint(GHTheme.green(4))
                Text(L("Terminaldeki GitHub CLI (gh) girişiyle bağlanır; ayrıca onay gerekmez."))
                    .font(.caption).foregroundStyle(GHTheme.muted)
            } else if !github.configured {
                Text(L("Giriş için GitHub CLI gerekli: `brew install gh` ve `gh auth login`.")).font(.caption).foregroundStyle(.orange)
            }
            if let e = github.error { Text(e).font(.callout).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func waiting(_ code: GitHubDeviceCode) -> some View {
        VStack(spacing: 14) {
            Text(L("Tarayıcıda bu kodu gir")).font(.title3.bold())
            Text(code.userCode).font(.system(size: 40, weight: .bold, design: .monospaced)).textSelection(.enabled)
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(GHTheme.card))
            Text(L("Kod panoya kopyalandı. Açılan GitHub sayfasına yapıştırıp “Authorize” de; gerisi kendiliğinden olur."))
                .foregroundStyle(GHTheme.muted).multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack {
                Button(L("Sayfayı yeniden aç")) { NSWorkspace.shared.open(code.verificationURI) }
                Button(L("Kodu kopyala")) { GitHubModel.copy(code.userCode) }
                Button(L("Vazgeç")) { github.cancelSignIn() }
            }
            ProgressView().controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Pano

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let p = github.profile, let s = github.stats {
                    cards(p, s)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("{0} katkı · son bir yıl", "\(p.total)")).font(.headline)
                        Heatmap(days: p.days)
                        Text(L("Commit {0} · Pull request {1} · Issue {2} · İnceleme {3}", "\(p.commits)", "\(p.pullRequests)", "\(p.issues)", "\(p.reviews)")
                             + (p.privateCount > 0 ? L(" · gizli depolarda {0}", "\(p.privateCount)") : ""))
                            .font(.caption).foregroundStyle(GHTheme.muted)
                    }
                    .padding(16).background(RoundedRectangle(cornerRadius: 12).fill(GHTheme.card))
                    repoList
                } else if github.loading {
                    ProgressView(L("Katkılar yükleniyor…")).frame(maxWidth: .infinity).padding(40)
                }
                if let e = github.error { Text(e).foregroundStyle(.red) }
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AsyncImage(url: github.profile?.avatarURL) { img in img.resizable() } placeholder: { Circle().fill(GHTheme.card) }
                .frame(width: 48, height: 48).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(github.profile?.name ?? github.profile?.login ?? "GitHub").font(.title2.bold())
                if let login = github.profile?.login {
                    Link("@\(login)", destination: URL(string: "https://github.com/\(login)")!).font(.callout)
                }
            }
            Spacer()
            if let t = github.lastUpdated {
                (Text(L("güncellendi") + " ") + Text(t, format: .relative(presentation: .named))).font(.caption).foregroundStyle(GHTheme.muted)
            }
            Button { Task { await github.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(github.loading).help(L("Şimdi tazele"))
            Menu {
                Button(L("Çıkış yap"), role: .destructive) { github.signOut() }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    private func cards(_ p: GitHubProfile, _ s: ContributionStats) -> some View {
        HStack(spacing: 12) {
            StatCard(title: L("Bugün"), value: "\(s.today)", note: L("katkı"))
            StatCard(title: L("Son 7 gün"), value: "\(s.lastSevenDays)", note: L("katkı"))
            StatCard(title: L("Seri"), value: "\(s.currentStreak) 🔥", note: s.currentStreak == 1 ? L("gün") : L("gün üst üste"),
                     highlight: s.currentStreak > 0 && s.currentStreak == s.longestStreak)
            StatCard(title: L("En uzun seri"), value: "\(s.longestStreak)", note: L("gün"))
            StatCard(title: L("Bu yıl"), value: "\(p.total)", note: L("katkı"))
        }
    }

    private var repoList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Son {0} gün · depolar", "\(GitHubModel.repoDays)")).font(.headline)
                Spacer()
                Text(L("{0} commit", "\(github.reposTotal)")).font(.caption).foregroundStyle(GHTheme.muted)
            }
            let top = github.repos.first?.commits ?? 1
            ForEach(github.repos.prefix(15)) { r in
                HStack(spacing: 10) {
                    Image(systemName: r.isPrivate ? "lock.fill" : "book.closed").font(.system(size: 10))
                        .foregroundStyle(GHTheme.muted).frame(width: 14)
                    Link(r.name.split(separator: "/").last.map(String.init) ?? r.name,
                         destination: URL(string: "https://github.com/\(r.name)")!)
                        .frame(width: 210, alignment: .leading).lineLimit(1)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 3).fill(GHTheme.green(3))
                            .frame(width: max(4, g.size.width * CGFloat(r.commits) / CGFloat(top)))
                    }
                    .frame(height: 10)
                    Text("\(r.commits)").font(.system(.callout, design: .monospaced)).frame(width: 44, alignment: .trailing)
                }
            }
            if github.repos.isEmpty && !github.loading {
                Text(L("Bu dönemde commit bulunamadı.")).foregroundStyle(GHTheme.muted)
            }
        }
        .padding(16).background(RoundedRectangle(cornerRadius: 12).fill(GHTheme.card))
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let note: String
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold()).foregroundStyle(GHTheme.muted)
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(highlight ? L("rekor serindesin") : note).font(.caption).foregroundStyle(highlight ? GHTheme.green(4) : GHTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(GHTheme.card))
    }
}

/// GitHub tarzı katkı ısı haritası.
private struct Heatmap: View {
    let days: [ContributionDay]
    static let cell: CGFloat = 11
    static let gap: CGFloat = 3

    var body: some View {
        let weeks = ContributionGrid.weeks(days)
        let labels = Dictionary(uniqueKeysWithValues: ContributionGrid.monthLabels(weeks).map { ($0.week, $0.name) })
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .trailing, spacing: Self.gap) {
                Text(" ").font(.system(size: 9)).frame(height: 12)
                ForEach(0..<7, id: \.self) { i in
                    Text(["", L("Pzt"), "", L("Çar"), "", L("Cum"), ""][i]).font(.system(size: 9)).foregroundStyle(GHTheme.muted)
                        .frame(height: Self.cell)
                }
            }
            HStack(alignment: .top, spacing: Self.gap) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { i, week in
                    VStack(spacing: Self.gap) {
                        Text(labels[i] ?? " ").font(.system(size: 9)).foregroundStyle(GHTheme.muted)
                            .fixedSize().frame(width: Self.cell, height: 12, alignment: .leading)
                        ForEach(0..<7, id: \.self) { d in
                            if d < week.count, let day = week[d] {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(GHTheme.green(ContributionGrid.level(day.count, in: days)))
                                    .frame(width: Self.cell, height: Self.cell)
                                    .help(L("{0}: {1} katkı", day.date, "\(day.count)"))
                            } else {
                                Color.clear.frame(width: Self.cell, height: Self.cell)
                            }
                        }
                    }
                }
            }
        }
        HStack(spacing: 4) {
            Spacer()
            Text(L("Az")).font(.system(size: 9)).foregroundStyle(GHTheme.muted)
            ForEach(0..<5, id: \.self) { l in
                RoundedRectangle(cornerRadius: 2).fill(GHTheme.green(l)).frame(width: Self.cell, height: Self.cell)
            }
            Text(L("Çok")).font(.system(size: 9)).foregroundStyle(GHTheme.muted)
        }
    }
}

enum GHTheme {
    static let background = Color(red: 0.965, green: 0.945, blue: 0.91)
    static let card = Color.white.opacity(0.7)
    static let text = Color(red: 0.17, green: 0.16, blue: 0.15)
    static let muted = Color(red: 0.50, green: 0.47, blue: 0.42)

    static func green(_ level: Int) -> Color {
        switch level {
        case 1: Color(red: 0.608, green: 0.914, blue: 0.659)
        case 2: Color(red: 0.251, green: 0.769, blue: 0.388)
        case 3: Color(red: 0.188, green: 0.631, blue: 0.306)
        case 4...: Color(red: 0.129, green: 0.431, blue: 0.224)
        default: Color(red: 0.88, green: 0.86, blue: 0.82)
        }
    }
}
