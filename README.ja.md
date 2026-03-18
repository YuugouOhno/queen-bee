# beeops

[English README](README.md)

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) 向け 3層マルチエージェント・オーケストレーションシステム。

**Queen → Leader → Worker** — GitHub Issue を自動的にサブタスクに分解し、git worktree で隔離された環境で並列実装を行い、コードレビューを実施し、CI をチェックします。すべて tmux 上でオーケストレーションされます。

## 仕組み

```
Queen (L1)                – GitHub Issue を読み込み、queue.yaml を構築、Leader をディスパッチ
  ├─ Leader (L2)          – Issue をサブタスクに分解、Worker をディスパッチ、PR を作成
  │    ├─ Worker (coder)  – 単一サブタスクの実装
  │    └─ Worker (tester) – サブタスクのテスト作成
  └─ Review Leader (L2)   – レビュー Worker をディスパッチ、結果を集約
       ├─ Worker (code-reviewer)  – コード品質レビュー
       ├─ Worker (security)       – セキュリティ脆弱性レビュー
       └─ Worker (test-auditor)   – テストカバレッジ監査
```

各レイヤーは tmux 内で個別の Claude Code インスタンスとして動作します。通信は YAML レポートと `tmux wait-for` シグナルで行われます。GitHub 以外の外部サーバー・データベース・API は不要です。

Worker は**多層コンテキスト注入**（ベース＋専門特化）を受け取ります：

| Worker ロール | ベースコンテキスト | 専門特化 |
|-------------|-------------|----------------|
| `worker-coder` | `worker-base.md` | `coder.md` |
| `worker-tester` | `worker-base.md` | `tester.md` |
| `worker-code-reviewer` | `reviewer-base.md` | `code-reviewer.md` |
| `worker-security` | `reviewer-base.md` | `security-reviewer.md` |
| `worker-test-auditor` | `reviewer-base.md` | `test-auditor.md` |

## 前提条件

- **Node.js** >= 18
- **git**
- **tmux**
- **python3**
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI (`claude`)
- [GitHub CLI](https://cli.github.com/) (`gh`) — Issue 同期と PR 操作に使用

## クイックスタート

```bash
# インストール
npm install beeops

# プロジェクトで初期化
cd your-project
npx beeops init

# Claude Code から起動
# Claude Code で /bee-dev と入力
```

以下がインストールされます：
- `/bee-dev` スラッシュコマンド
- 4つのスキル（dispatch, leader-dispatch, task-decomposer, issue-sync）
- コンテキスト注入用の UserPromptSubmit フック

## コマンド

### `/bee-dev` — 開発オーケストレーション

GitHub Issue に対して Queen → Leader → Worker の全パイプラインを実行します。Issue を同期し、git worktree で隔離された環境に Leader をディスパッチし、実装・レビュー・CI チェックまで自動で行います。

```
Queen (L1)
  ├─ Leader (L2)          – Issue をサブタスクに分解、Worker をディスパッチ、PR を作成
  │    ├─ Worker (coder)
  │    └─ Worker (tester)
  └─ Review Leader (L2)   – レビュー Worker をディスパッチ、結果を集約
       ├─ Worker (code-reviewer)
       ├─ Worker (security)
       └─ Worker (test-auditor)
```

### `/bee-content` — コンテンツ品質ループ

Creator と Reviewer が反復してコンテンツを改善し、品質スコアが閾値を超えるまでループします。

```
/bee-content "beeopsについてのブログ記事を書いて" --criteria "正確、800字以内" --threshold 85
```

Creator がコンテンツを書いて自己採点し、Reviewer が独立して評価・フィードバックします。閾値に達するか `--max-loops` に達するまでループが続きます。

| オプション | 説明 |
|-----------|------|
| `--criteria "..."` | コンテンツの品質基準 |
| `--threshold N` | 合格スコア（0–100、デフォルト: 80） |
| `--max-loops N` | Creator ↔ Reviewer の最大ループ回数（デフォルト: 3） |
| `--count N` | バッチモードで生成する件数 |
| `--name <name>` | 後で再開するためのセッション名 |

## init オプション

```bash
npx beeops init                    # .claude/settings.local.json にフック登録（デフォルト）
npx beeops init --shared           # .claude/settings.json にフック登録（チーム共有）
npx beeops init --global           # ~/.claude/settings.json にフック登録（全プロジェクト）
npx beeops init --with-contexts    # カスタマイズ用にコンテキストファイルをコピー
npx beeops init --locale ja        # ロケールを日本語に設定
```

## 多言語サポート

beeops はエージェントプロンプトの多言語ロケールに対応しています。現在利用可能：**en**（英語、デフォルト）、**ja**（日本語）。

```bash
# init 時に設定
npx beeops init --locale ja

# 実行時にオーバーライド
BO_LOCALE=ja /bee-dev
```

コンテキストファイルは 4段階のフォールバックで解決されます：
1. プロジェクトローカル＋ロケール (`<project>/.beeops/contexts/<locale>/<file>`)
2. プロジェクトローカル・ルート (`<project>/.beeops/contexts/<file>`)
3. パッケージ＋ロケール (`<pkg>/contexts/<locale>/<file>`)
4. パッケージ・ルート (`<pkg>/contexts/<file>`)

## エージェント動作のカスタマイズ

```bash
# デフォルトコンテキストを編集用にコピー
npx beeops init --with-contexts
```

プロジェクト内に `.beeops/contexts/` が作成されます。任意のファイルを編集してエージェントの動作をカスタマイズできます。ファイルを削除するとパッケージのデフォルトにフォールバックします。

主要ファイル：
- `queen.md` — Queen オーケストレータープロンプト
- `leader.md` — 実装 Leader プロンプト
- `review-leader.md` — レビュー Leader プロンプト
- `worker-base.md` — Worker ベース（自律ルール、レポート形式）
- `coder.md` — コーダー特化（コーディング規約、Fail Fast、禁止パターン）
- `tester.md` — テスター特化（テスト計画、境界値、Given-When-Then）
- `reviewer-base.md` — レビュアーベース（レビュー手順、判定ルール）
- `code-reviewer.md` — コードレビュー特化（設計、品質、API、パフォーマンス）
- `security-reviewer.md` — セキュリティ特化（OWASP Top 10、インジェクション、認証）
- `test-auditor.md` — テスト監査特化（カバレッジ、エッジケース、リグレッション）
- `agent-modes.json` — 環境変数からコンテキストファイルへのマッピング

## アーキテクチャ

### ワークフロー

1. **Issue 同期**: Queen が GitHub Issue を取得 → `queue.yaml` を構築
2. **ディスパッチ**: Queen が git worktree 付きの新しい tmux ウィンドウで Leader を起動
3. **実装**: Leader が Issue を分解 → tmux ペインで Worker を起動
4. **PR 作成**: 最終 Worker がプルリクエストを作成
5. **レビュー**: Queen が Review Leader をディスパッチ → レビュー Worker を起動
6. **CI チェック**: 承認後、Queen が CI ステータスを監視
7. **修正ループ**: レビュー/CI 失敗時、Queen が修正モードで Leader を再起動（最大3回）

### tmux レイアウト

```
tmux session "bee-dev"
├── [queen]     👑 Queen オーケストレーター（金枠）
├── [issue-42]  👑 Issue #42 の Leader（青枠）
│   ├── pane 0: Leader
│   ├── pane 1: ⚡ Worker (coder, 緑枠)
│   └── pane 2: 🧪 Worker (tester, シアン枠)
└── [review-42] 🔮 Issue #42 の Review Leader（マゼンタ枠）
    ├── pane 0: Review Leader
    ├── pane 1: 🔍 Worker (code-reviewer, 青枠)
    ├── pane 2: 🛡 Worker (security, 赤枠)
    └── pane 3: 🧪 Worker (test-auditor, 黄枠)
```

`tmux attach -t bee-dev` で全エージェントの動作をリアルタイムに確認できます。

## アップデート

```bash
npm update beeops
npx beeops init
```

パッケージを更新し、コマンド・スキル・フックを再デプロイします。`.beeops/contexts/` のカスタムコンテキストはそのまま保持されます。

## 検証

```bash
npx beeops check
```

コマンド、スキル、フック登録、パッケージ解決など、すべてのコンポーネントが正しくインストールされているか検証します。

## ライセンス

MIT

## 作者

[YuugouOhno](https://github.com/YuugouOhno)
