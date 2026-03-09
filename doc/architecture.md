# beeops アーキテクチャ解説

Claude Code 上で動作する 3 層マルチエージェントオーケストレーションシステム。
GitHub Issue を入力とし、実装・テスト・レビュー・CI チェックまでを自動化する。

---

## 目次

1. [全体像](#1-全体像)
2. [設計思想](#2-設計思想)
3. [3 層エージェント階層](#3-3-層エージェント階層)
4. [実行基盤: tmux セッション管理](#4-実行基盤-tmux-セッション管理)
5. [環境変数チェーン](#5-環境変数チェーン)
6. [コンテキスト注入とロケールフォールバック](#6-コンテキスト注入とロケールフォールバック)
7. [スキルシステム](#7-スキルシステム)
8. [状態管理: queue.yaml](#8-状態管理-queueyaml)
9. [レポートによるエージェント間通信](#9-レポートによるエージェント間通信)
10. [ワークツリー分離](#10-ワークツリー分離)
11. [レビューシステム](#11-レビューシステム)
12. [CLI とパッケージ配布](#12-cli-とパッケージ配布)
13. [設定とカスタマイズ](#13-設定とカスタマイズ)
14. [End-to-End 実行フロー](#14-end-to-end-実行フロー)
15. [やりたかったこと](#15-やりたかったこと)

---

## 1. 全体像

```
┌─────────────────────────────────────────────────────────────┐
│                    ユーザー: /bo 実行                         │
└──────────────────────────┬──────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  L1: Queen（オーケストレーター）                               │
│  ・GitHub Issues → queue.yaml 同期                           │
│  ・タスク優先度付け・依存関係解決                                │
│  ・Leader / Review Leader のディスパッチ                       │
│  ・CI チェック・修正ループ管理                                  │
└────────┬───────────────────────────────────┬────────────────┘
         ▼                                   ▼
┌─────────────────────┐         ┌──────────────────────────┐
│  L2: Leader          │         │  L2: Review Leader        │
│  ・Issue 分解         │         │  ・PR 複雑度評価           │
│  ・Worker 起動        │         │  ・レビュー Worker 起動     │
│  ・品質評価           │         │  ・結果集約・判定           │
│  ・PR 作成            │         │  ・反迎合チェック           │
└────────┬────────────┘         └────────┬─────────────────┘
         ▼                                ▼
┌─────────────────────────────────────────────────────────────┐
│  L3: Workers（専門家）                                        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ ┌─────┐ │
│  │ Coder    │ │ Tester   │ │ Code     │ │Security│ │Test │ │
│  │          │ │          │ │ Reviewer │ │Reviewer│ │Audit│ │
│  └──────────┘ └──────────┘ └──────────┘ └────────┘ └─────┘ │
└─────────────────────────────────────────────────────────────┘
```

beeops は **「コマンドひとつで Issue を片付ける」** ことを目指したシステムである。
ユーザーが `/bo` を実行すると tmux セッションが立ち上がり、Queen が GitHub Issues を読み込んで
タスクキューを構築し、Leader と Worker を次々と起動して実装・テスト・レビューを回す。

---

## 2. 設計思想

### 2.1 外部サービスゼロ

API サーバーもデータベースも不要。必要なのは tmux, git, claude, gh だけ。
全てがローカルマシン上で完結し、状態は YAML ファイルとレポートファイルで管理する。

### 2.2 エージェント間の疎結合

エージェント同士は **直接通信しない**。通信手段は以下の 3 つだけ:

| 手段 | 用途 |
|------|------|
| **YAML レポートファイル** | 結果報告（成功/失敗、要修正箇所など） |
| **tmux wait-for シグナル** | 完了通知（ビジーウェイティング回避） |
| **プロンプトファイル** | 指示の受け渡し（親 → 子） |

これにより各エージェントは独立して動作し、障害が波及しにくい。

### 2.3 ツール制限による責務分離

各エージェントは使えるツールが厳密に制限されている:

| レイヤー | Write/Edit | Bash | Skill | 役割 |
|----------|-----------|------|-------|------|
| Queen | ❌ | ✅ | ✅ | 指揮のみ、コードを書かない |
| Leader | ✅ | ✅ | ✅ | Worker 管理、直接実装しない |
| Review Leader | ❌ | ✅ | ✅ | レビュー管理、コードを変更しない |
| Worker (Coder/Tester) | ✅ | ✅ | ✅* | 実装に集中 |
| Worker (Reviewer) | ❌ | ✅ | ✅* | 読むだけ |

\* Worker はプロジェクト固有スキルを使用可能。ただしオーケストレーション系スキル（`bo-dispatch`, `bo-leader-dispatch`, `bo-issue-sync`）はコンテキストで禁止。

Queen がコードを書けないのは設計上の意図。オーケストレーターがコードに手を出すと
責務が混在し、長時間稼働でコンテキストウィンドウを消費する。

### 2.4 自律動作

全エージェントは **ユーザーに質問しない**。AskUserQuestion は禁止。
判断に迷ったら自分で決定し、その理由をログ/レポートに記録する。
これにより、ユーザーが離席していても処理が止まらない。

### 2.5 人間が読める状態管理

queue.yaml は plain YAML。テキストエディタで開いて状態を確認・修正できる。
レポートも YAML。機械可読かつ人間可読な形式を一貫して採用。

### 2.6 カスタマイズ可能なコンテキスト

パッケージにはデフォルトのコンテキストファイルが同梱されるが、
プロジェクトローカルに同名ファイルを置くだけでオーバーライドできる。
削除すればパッケージデフォルトに自動フォールバック。

---

## 3. 3 層エージェント階層

### 3.1 L1: Queen（オーケストレーター）

```
環境変数: BO_QUEEN=1
コンテキスト: queen.md
最大ターン: 無制限（長期稼働）
```

Queen はシステム全体の司令塔。以下の 3 フェーズで動作する:

| フェーズ | 内容 |
|----------|------|
| Phase 0 | ユーザー指示の分析（引数 / settings.json / インタラクティブ） |
| Phase 1 | `bo-issue-sync` で GitHub Issues → queue.yaml に同期 |
| Phase 2 | タスクループ: キューから取り出し → ディスパッチ → レポート処理 → 次のタスク |

**禁止事項**: コード記述、git 操作、PR 作成、claude の直接起動

Queen がやるのは「誰に何をやらせるか決めること」だけ。

### 3.2 L2: Leader（実装リーダー / レビューリーダー）

#### Implementation Leader
```
環境変数: BO_LEADER=1
コンテキスト: leader.md
最大ターン: 80
```

- Issue を読んでサブタスクに分解
- Worker のプロンプトファイルを作成
- Worker を並列/順次に起動
- 品質を評価し、不十分なら再試行（最大 2 回）
- PR を作成し、サマリーレポートを書く

#### Review Leader
```
環境変数: BO_REVIEW_LEADER=1
コンテキスト: review-leader.md
最大ターン: 40
```

- PR の複雑度を評価（simple / standard / complex）
- レビュー Worker を並列起動
- 結果を集約し、最終判定（approve / fix_required）
- **反迎合チェック**: 全 Worker が approve した場合、本当に問題がないか再確認

### 3.3 L3: Workers（専門家）

5 種類の専門 Worker が存在する:

| Worker | 環境変数 | 最大ターン | Write/Edit | 役割 |
|--------|---------|-----------|-----------|------|
| Coder | `BO_WORKER_CODER` | 30 | ✅ | コード実装 |
| Tester | `BO_WORKER_TESTER` | 30 | ✅ | テスト作成 |
| Code Reviewer | `BO_WORKER_CODE_REVIEWER` | 15 | ❌ | コード品質レビュー |
| Security Reviewer | `BO_WORKER_SECURITY` | 15 | ❌ | セキュリティレビュー |
| Test Auditor | `BO_WORKER_TEST_AUDITOR` | 15 | ❌ | テスト監査 |

Worker は全て **自律動作** で、プロンプトファイルに書かれた指示に従い、
完了したらレポートファイルを書いて tmux シグナルで親に通知する。

---

## 4. 実行基盤: tmux セッション管理

### 4.1 セッション構造

```
tmux session: bo
├── window: queen          ← Queen エージェント（黄色ボーダー）
├── window: issue-42       ← Leader + Workers（青ボーダー）
│   ├── pane: leader       ← Leader エージェント
│   ├── pane: worker-coder-42-impl-1   ← 水平分割（緑ボーダー）
│   ├── pane: worker-coder-42-impl-2   ← 水平分割（緑ボーダー）
│   └── pane: worker-tester-42-test-1  ← 水平分割（シアンボーダー）
├── window: review-42      ← Review Leader + Review Workers（マゼンタボーダー）
│   ├── pane: review-leader
│   ├── pane: code-reviewer-42-review
│   ├── pane: security-42-security
│   └── pane: test-auditor-42-audit
└── (次の issue window...)
```

### 4.2 ペインのライフサイクル

1. **起動**: タイトルに絵文字 + ロール名を表示（例: `👑 queen`, `⚡ worker-coder`）
2. **動作中**: ロール固有の色でボーダーが表示される
3. **完了**: タイトルが ✅ or ❌ に変更、ボーダーがグレーに変化
4. **保持**: `remain-on-exit` で完了後もペインが残り、ログを確認できる

### 4.3 イベント駆動の完了通知

```
Worker 完了 → tmux wait-for -S leader-{issue}-wake → Leader が検知
Leader 完了 → tmux wait-for -S queen-wake → Queen が検知
```

ポーリングではなくイベント駆動。CPU を浪費しない。
タイムアウト付き（Leader: 30 分、Review Leader: 20 分）で、
ハングしたエージェントを検知できる。

---

## 5. 環境変数チェーン

beeops の核心的な仕組み。ハードコードされたパスを完全に排除する。

```
/bo 実行
  ↓
PKG_DIR = require.resolve('beeops/package.json') のディレクトリ
  ↓
BO_SCRIPTS_DIR = "$PKG_DIR/scripts"
BO_CONTEXTS_DIR = "$PKG_DIR/contexts"
  ↓  tmux 環境変数として注入
Queen セッション
  ↓  launch-leader.sh が BO_* を引き継ぎ
Leader セッション（ラッパースクリプト内で export）
  ↓  launch-worker.sh が BO_* を引き継ぎ
Worker セッション（ラッパースクリプト内で export）
  ↓  bo-prompt-context.py が BO_CONTEXTS_DIR を使用
コンテキスト解決
```

この連鎖により、npm でグローバルインストールしても、ローカルインストールしても、
npm link でリンクしても、パスが正しく解決される。

---

## 6. コンテキスト注入とロケールフォールバック

### 6.1 フックの仕組み

Claude Code の `UserPromptSubmit` フックを利用。
ユーザーがプロンプトを送信するたびに `bo-prompt-context.py` が実行され、
現在のエージェントロールに応じたコンテキストが注入される。

```
ユーザーのプロンプト送信
  ↓
Claude Code が UserPromptSubmit フックを発火
  ↓
bo-prompt-context.py 実行
  ↓
環境変数チェック（BO_QUEEN? BO_LEADER? BO_WORKER_CODER? ...）
  ↓
agent-modes.json からコンテキストファイル名を取得
  ↓
4 段階フォールバックでファイルを解決
  ↓
stdout に出力 → Claude Code がシステムコンテキストとして注入
```

### 6.2 4 段階フォールバック

コンテキストファイル（例: `queen.md`）は以下の順で検索される:

```
1. プロジェクトローカル（ロケール付き）:
   <project>/.claude/beeops/contexts/{LOCALE}/queen.md

2. プロジェクトローカル（ルート）:
   <project>/.claude/beeops/contexts/queen.md

3. パッケージ（ロケール付き）:
   <pkg>/contexts/{LOCALE}/queen.md

4. パッケージ（ルート）:
   <pkg>/contexts/queen.md
```

ローカルファイルが最優先。なければパッケージデフォルトにフォールバック。
ロケールは `BO_LOCALE` 環境変数 → `.claude/beeops/locale` ファイル → `"en"` の順で決定。

### 6.3 マルチファイルコンテキスト

Worker はベースコンテキスト + 専門コンテキストの 2 ファイルが連結される:

```json
"BO_WORKER_CODER": {
  "context": ["worker-base.md", "coder.md"]
}
```

`worker-base.md` は全 Worker 共通のルール（自律動作、エラーハンドリング方針など）。
`coder.md` は Coder 固有のルール（実装方針、コード原則など）。

### 6.4 agent-modes.json

環境変数とコンテキストファイルのマッピングを定義:

```json
{
  "modes": {
    "BO_QUEEN":           { "context": ["queen.md"] },
    "BO_LEADER":          { "context": ["leader.md"] },
    "BO_REVIEW_LEADER":   { "context": ["review-leader.md"] },
    "BO_WORKER_CODER":    { "context": ["worker-base.md", "coder.md"] },
    "BO_WORKER_TESTER":   { "context": ["worker-base.md", "tester.md"] },
    "BO_WORKER_CODE_REVIEWER": { "context": ["reviewer-base.md", "code-reviewer.md"] },
    "BO_WORKER_SECURITY": { "context": ["reviewer-base.md", "security-reviewer.md"] },
    "BO_WORKER_TEST_AUDITOR": { "context": ["reviewer-base.md", "test-auditor.md"] }
  },
  "default_context": "default.md"
}
```

このファイル自体もロケールフォールバックの対象。

---

## 7. スキルシステム

複雑なワークフローを Markdown スキルファイルとしてカプセル化。
エージェントは `Skill` ツールでスキルを呼び出す。

### 7.1 スキル一覧

| スキル | 使用者 | 目的 |
|--------|--------|------|
| `bo-dispatch` | Queen | Leader/Review Leader の起動・待機・レポート処理・次アクション決定 |
| `bo-leader-dispatch` | Leader, Review Leader | Worker の起動・待機・品質評価 |
| `bo-task-decomposer` | Queen, Leader | タスクの詳細分解 |
| `bo-issue-sync` | Queen | GitHub Issues → queue.yaml 同期 |
| `bo-review-backend` | Code Reviewer | バックエンドコードレビュー |
| `bo-review-frontend` | Code Reviewer | フロントエンドコードレビュー |
| `bo-review-database` | Code Reviewer | DB スキーマ・クエリレビュー |
| `bo-review-operations` | Reviewer | インフラ・運用設定レビュー |
| `bo-review-security` | Security Reviewer | セキュリティレビュー |
| `bo-review-process` | Reviewer | レビュープロセス改善 |

### 7.2 スキルの設計パターン

スキルは **手続き（Procedure）** を定義する。例えば `bo-dispatch` は:

1. `launch-leader.sh` を Bash で実行
2. `tmux wait-for queen-wake` でタイムアウト付き待機
3. レポートファイルを読み取り
4. 次アクションを判定（レビュー開始? 修正ループ? CI チェック?）
5. queue.yaml のステータスを更新

スキル内にロジックが記述されるため、エージェントの動作が予測可能で再現性が高い。

---

## 8. 状態管理: queue.yaml

### 8.1 構造

```yaml
version: 1
tasks:
  - id: "ISSUE-42"
    issue: 42
    title: "ユーザー認証の実装"
    type: issue
    status: queued
    priority: high
    branch: "feat/issue-42"
    depends_on: []
    review_count: 0
    pr: null
    blocked_reason: null
    log:
      - "2026-03-08T12:00:00Z created from gh issue"
```

### 8.2 ステータス遷移

```
raw → queued → dispatched → leader_working → review_dispatched → reviewing → done
                                  ↓
                            fix_required (最大 3 回)
                                  ↓
                              fixing → review_dispatched（再レビュー）
                                  ↓ (3 回超過)
                                stuck

既存 PR 検出時の短絡パス:
  raw → review_dispatched → reviewing → done
```

- `raw`: Issue から取り込んだ直後
- `queued`: 優先度付けされキュー投入済み
- `dispatched`: Leader に割り当て済み
- `leader_working`: Leader が作業中
- `review_dispatched`: Review Leader に割り当て済み
- `reviewing`: レビュー中
- `fix_required`: 修正が必要（review_count をインクリメント）
- `fixing`: 修正中（Leader が fix モードで再起動）
- `ci_checking`: CI ステータスをポーリング中
- `done`: 完了
- `stuck`: 修正ループ上限超過 or 解決不能
- `error`: 予期しないエラー

### 8.3 依存関係

```yaml
depends_on: ["ISSUE-40", "ISSUE-41"]
```

Queen は依存先が全て `done` になるまでそのタスクをスキップする。
Issue 本文の「depends on #XX」や関連ラベルから自動推定。

---

## 9. レポートによるエージェント間通信

### 9.1 レポートの種類

```
.claude/tasks/reports/
├── leader-42.yaml                  ← 基本レポート（シェルが自動生成）
├── leader-42-summary.yaml          ← 詳細レポート（Leader が記述）
├── review-leader-42.yaml           ← 基本レポート
├── review-leader-42-verdict.yaml   ← 判定レポート（Review Leader が記述）
├── worker-42-impl-1.yaml           ← 基本レポート
├── worker-42-impl-1-detail.yaml    ← 詳細レポート（Worker が記述）
└── processed/                      ← 処理済みアーカイブ
```

### 9.2 基本レポート（自動生成）

シェルラッパーが exit code に基づいて自動生成。最低限の完了通知:

```yaml
issue: 42
role: worker-coder
subtask_id: impl-1
status: completed  # or failed
exit_code: 0
branch: feat/issue-42
timestamp: "2026-03-08T12:30:00Z"
```

### 9.3 詳細レポート（エージェント記述）

エージェントが判断や結果を記録。Queen / Leader はこれを読んで次の判断を行う:

```yaml
# review-leader-42-verdict.yaml
complexity: standard
council_members: [code-reviewer, security-reviewer, test-auditor]
final_verdict: fix_required
findings:
  - severity: high
    file: src/auth.ts
    description: "パスワードハッシュが平文保存"
anti_sycophancy_triggered: false
```

### 9.4 通信フロー

```
Leader → プロンプトファイル作成 → Worker 起動
Worker → 作業実行 → レポートファイル作成 → tmux signal
Leader → レポート読み取り → 品質評価 → サマリーレポート作成 → tmux signal
Queen → レポート読み取り → 次アクション決定 → processed/ に移動
```

---

## 10. ワークツリー分離

### 10.1 なぜワークツリーか

複数 Issue を並列処理する場合、ブランチの切り替えが衝突する。
git worktree を使えば、各 Issue が独立したディレクトリで作業でき、
メインリポジトリは Queen が使い続けられる。

### 10.2 ワークツリーの管理

```
.claude/worktrees/
├── feat/issue-42/     ← Issue #42 の Leader と Worker が共有
├── fix/issue-55/      ← Issue #55 の Leader と Worker が共有
└── ...
```

- **Leader**: ワークツリーを作成、Worker と共有
- **Worker**: Leader のワークツリーを検出して再利用
- **Fix モード**: 既存ワークツリーをそのまま再利用（再作成しない）
- **完了後**: PR マージ後にワークツリーとブランチを削除

### 10.3 シンボリックリンク

ワークツリーでは `node_modules` などの重いディレクトリをシンボリックリンクで共有:

```bash
ln -sf "$MAIN_REPO/node_modules" "$WORKTREE_DIR/node_modules"
ln -sf "$MAIN_REPO/.next" "$WORKTREE_DIR/.next"
```

---

## 11. レビューシステム

### 11.1 レビュー Council

Review Leader は「レビュー会議」を構成する。PR の複雑度に応じて
異なるメンバーを招集:

| 複雑度 | メンバー |
|--------|---------|
| simple | Code Reviewer のみ |
| standard | Code Reviewer + Security Reviewer |
| complex | Code Reviewer + Security Reviewer + Test Auditor |

### 11.2 反迎合チェック（Anti-Sycophancy）

全 Worker が approve した場合、Review Leader は疑いの目を向ける:

1. 変更量に対して指摘がゼロは不自然ではないか？
2. セキュリティ上の懸念が本当にないか？
3. テストカバレッジは十分か？

必要に応じて追加検証を行い、安易な approve を防ぐ。

### 11.3 修正ループ

```
Review Leader: fix_required
  ↓
Queen: Leader を fix モードで再起動（status: fixing）
  ↓
Leader: 修正作業（既存ワークツリーを再利用）
  ↓
Queen: Review Leader を再起動（review_count++）
  ↓
(最大 3 回まで繰り返し、超過で stuck)
```

### 11.4 リソースルーティング

Code Reviewer は変更ファイルの種類に応じて専門レビュースキルを選択:

| ファイル種類 | 使用スキル |
|-------------|-----------|
| `.ts`, `.py`（サーバー側） | `bo-review-backend` |
| `.tsx`, `.vue` | `bo-review-frontend` |
| `.sql`, `.prisma` | `bo-review-database` |
| `Dockerfile`, `.yml`（CI/CD） | `bo-review-operations` |
| 認証・暗号関連 | `bo-review-security`（常時ペア） |

---

## 12. CLI とパッケージ配布

### 12.1 インストールと初期化

```bash
npm install beeops          # パッケージインストール
npx beeops init             # プロジェクトに beeops をセットアップ
npx beeops init --locale ja # 日本語コンテキストで初期化
npx beeops check            # インストール状態の確認
```

### 12.2 init が行うこと

1. 前提条件チェック（Node.js 18+, git, tmux, python3, claude, gh）
2. プロジェクトルートを `git rev-parse --show-toplevel` で検出
3. `.claude/commands/bo.md` をコピー
4. 10 個のスキルを `.claude/skills/` にコピー
5. `UserPromptSubmit` フックを設定ファイルに登録
6. ロケール設定を `.claude/beeops/locale` に保存
7. `.gitignore` にランタイムアーティファクトを追加
8. `--with-contexts` 時: コンテキストファイルをローカルにコピー

### 12.3 フック登録先のオプション

| オプション | 登録先 | 用途 |
|-----------|--------|------|
| `--local`（デフォルト） | `.claude/settings.local.json` | 個人利用 |
| `--shared` | `.claude/settings.json` | チーム共有（git にコミット） |
| `-g`, `--global` | `~/.claude/settings.json` | 全プロジェクト共通 |

### 12.4 npm パッケージの構成

```
beeops/
├── bin/beeops.js        ← CLI エントリポイント
├── scripts/             ← launch-leader.sh, launch-worker.sh
├── hooks/               ← bo-prompt-context.py
├── contexts/            ← 全コンテキストファイル（en/, ja/）
├── skills/              ← 10 スキル
└── command/             ← bo.md
```

---

## 13. 設定とカスタマイズ

### 13.1 settings.json（実行設定）

`.claude/beeops/settings.json` で `/bo` の実行動作を事前設定:

```json
{
  "issues": [42, 55],
  "assignee": "me",
  "skip_review": false,
  "priority": "medium",
  "labels": ["bug", "feature"]
}
```

### 13.2 設定の優先順位

```
1. /bo の引数（最優先）
2. .claude/beeops/settings.json
3. インタラクティブプロンプト（設定なし時）
```

### 13.3 コンテキストのカスタマイズ

```bash
npx beeops init --with-contexts --locale ja
```

これでプロジェクトローカルにコンテキストファイルがコピーされ、
自由に編集できる。不要なカスタマイズを削除すればパッケージデフォルトにフォールバック。

---

## 14. End-to-End 実行フロー

Issue #42「ユーザー認証の実装」を例にした完全な実行フロー:

```
1. ユーザー: /bo 実行
   ↓
2. bo.md: パッケージパス解決 → tmux session "bo" 作成 → Queen 起動
   ↓
3. Queen Phase 0: 実行モード判定（引数 / settings / インタラクティブ）
   ↓
4. Queen Phase 1: bo-issue-sync スキル起動
   ├── gh issue list で Issue 取得
   ├── 既存 PR 検出
   ├── queue.yaml に追加（priority: high, status: queued）
   └── 依存関係解析
   ↓
5. Queen Phase 2: タスクループ開始
   ├── ISSUE-42 を選択（高優先度、依存なし）
   ├── status: dispatched に更新
   └── bo-dispatch スキル起動
   ↓
6. bo-dispatch: launch-leader.sh 実行
   ├── git worktree 作成: .claude/worktrees/feat/issue-42
   ├── プロンプトファイル作成: leader-42.md
   ├── tmux window "issue-42" 作成
   ├── Leader エージェント起動
   └── tmux wait-for queen-wake（30 分タイムアウト）
   ↓
7. Leader: Issue 分析 → サブタスク分解
   ├── worker-42-impl-api.md（API 実装）
   ├── worker-42-impl-db.md（DB 層実装）
   └── worker-42-test-auth.md（テスト作成）
   ↓
8. Leader: bo-leader-dispatch で Worker 起動
   ├── worker-coder × 2（並列: API + DB）
   └── worker-tester × 1（順次: テスト）
   ↓
9. Workers: 各ペインで並列実行
   ├── Coder #1: API ルート実装 → レポート → signal
   ├── Coder #2: DB 層実装 → レポート → signal
   └── Tester: テスト作成 → レポート → signal
   ↓
10. Leader: 品質評価 → PR 作成 → サマリーレポート → Queen に signal
    ↓
11. Queen: レポート読み取り → status: review_dispatched
    ↓
12. bo-dispatch: Review Leader 起動
    ├── tmux window "review-42" 作成
    └── tmux wait-for queen-wake（20 分タイムアウト）
    ↓
13. Review Leader: 複雑度評価 → Worker 起動
    ├── Code Reviewer: コード品質チェック
    ├── Security Reviewer: セキュリティチェック
    └── Test Auditor: テスト監査
    ↓
14. Review Leader: 結果集約 → 反迎合チェック → 判定レポート
    ↓
15. Queen: 判定処理
    ├── approve → CI チェック（gh pr checks）→ done
    └── fix_required → Leader を fix モードで再起動（最大 3 回）
    ↓
16. 完了後: ワークツリー削除、tmux window クリーンアップ
```

---

## 15. やりたかったこと

### 15.1 「Issue を渡したら全部やってくれる」世界

開発者が Issue を書いて `/bo` を叩けば、実装・テスト・レビュー・CI まで
自動で回る。人間はレビュー結果を確認して approve するだけ。

### 15.2 AI エージェントの「組織化」

単一の AI エージェントには限界がある:
- コンテキストウィンドウの制約
- 一度に一つのことしかできない
- 長時間実行で精度が低下する

beeops は人間の組織構造（経営層 → マネージャー → 実務者）を模倣し、
各エージェントの責務を限定することでこれらの制約を回避する。

### 15.3 品質の担保

AI が書いたコードを AI がレビューする。しかも:
- 5 種類の専門レビュアーが異なる視点でチェック
- 反迎合チェックで「全部 OK」の安易な判定を防ぐ
- 修正ループで指摘を反映させる仕組み

### 15.4 npm パッケージとしての配布

`npm install` → `npx beeops init` だけでどのプロジェクトにも導入できる。
環境変数チェーンとコンテキストフォールバックにより、
インストール方法に依存しない柔軟な配置を実現。

### 15.5 カスタマイズ可能な AI エージェントの振る舞い

コンテキストファイルを差し替えるだけで、エージェントの振る舞いを変えられる。
例えば:
- `coder.md` を書き換えてコーディング規約を変更
- `security-reviewer.md` を書き換えてセキュリティ基準を厳格化
- ロケールを追加して多言語チームに対応

全てがテキストファイルであり、コードの変更なしにカスタマイズできる。

### 15.6 透明性と可視性

- tmux で全エージェントの動作がリアルタイムに見える
- queue.yaml でタスクの進行状況がわかる
- レポートファイルで判断の根拠が追跡できる
- 全てが plain text / YAML で、ブラックボックスがない
