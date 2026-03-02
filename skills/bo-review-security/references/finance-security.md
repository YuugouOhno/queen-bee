# 金融系セキュリティ詳細ガイド

金融・決済・ポイント等の重要トランザクションを扱う場合の詳細なセキュリティチェックリスト。

---

## 1. レースコンディション対策

### 1.1 楽観的ロック

データ競合を検出するためのバージョン管理。

```typescript
// Prismaでの実装例
const updated = await prisma.account.update({
  where: {
    id: accountId,
    version: currentVersion, // バージョンチェック
  },
  data: {
    balance: { decrement: amount },
    version: { increment: 1 },
  },
});

if (!updated) {
  throw new OptimisticLockError('データが更新されました。再試行してください');
}
```

### 1.2 悲観的ロック

トランザクション中に他のアクセスをブロック。

```typescript
// SELECT FOR UPDATEの使用
await prisma.$transaction(async (tx) => {
  // 行ロックを取得
  const account = await tx.$queryRaw`
    SELECT * FROM accounts WHERE id = ${accountId} FOR UPDATE
  `;

  // 残高チェック
  if (account.balance < amount) {
    throw new InsufficientBalanceError();
  }

  // 更新
  await tx.account.update({
    where: { id: accountId },
    data: { balance: { decrement: amount } },
  });
});
```

### 1.3 チェックリスト

| 項目                        | 必須 | 備考             |
| --------------------------- | ---- | ---------------- |
| version列の追加             | ✅   | 楽観的ロック用   |
| 更新時のバージョンチェック  | ✅   | WHERE句に含める  |
| 残高変更はSELECT FOR UPDATE | ✅   | 悲観的ロック     |
| ロック取得順序の統一        | ✅   | デッドロック防止 |
| 並行リクエストテストの実施  | ✅   | 100並列等で検証  |

---

## 2. トランザクション整合性

### 2.1 トランザクション分離レベル

| レベル          | 用途                 | PostgreSQLデフォルト |
| --------------- | -------------------- | -------------------- |
| READ COMMITTED  | 一般的なCRUD         | ✅                   |
| REPEATABLE READ | レポート生成、集計   |                      |
| SERIALIZABLE    | 金融トランザクション | 推奨                 |

```typescript
// Serializableトランザクション
await prisma.$transaction(
  async (tx) => {
    // 金融処理
  },
  {
    isolationLevel: 'Serializable',
  }
);
```

### 2.2 アトミック操作

```typescript
// ❌ 悪い例: 残高チェックと更新が分離
const account = await prisma.account.findUnique({ where: { id } });
if (account.balance >= amount) {
  await prisma.account.update({ where: { id }, data: { balance: { decrement: amount } } });
}

// ✅ 良い例: 単一のアトミック操作
const result = await prisma.account.updateMany({
  where: {
    id: accountId,
    balance: { gte: amount }, // 条件と更新を一体化
  },
  data: {
    balance: { decrement: amount },
  },
});

if (result.count === 0) {
  throw new InsufficientBalanceError();
}
```

### 2.3 チェックリスト

| 項目                               | 必須 | 備考                      |
| ---------------------------------- | ---- | ------------------------- |
| 複数テーブル更新はトランザクション | ✅   | 部分的コミット防止        |
| 金融処理はSerializable             | ✅   | 最高分離レベル            |
| 残高チェックはアトミック           | ✅   | 読み取り→更新を分離しない |
| ロールバック処理の実装             | ✅   | 外部API呼び出し時         |

---

## 3. 二重処理防止（べき等性）

### 3.1 べき等性キー

```typescript
// クライアント側: 一意のキーを生成
const idempotencyKey = crypto.randomUUID();

// サーバー側: キーをチェック
async function processPayment(key: string, data: PaymentData) {
  // 既存のリクエストをチェック
  const existing = await redis.get(`idempotency:${key}`);
  if (existing) {
    return JSON.parse(existing); // 前回の結果を返す
  }

  // 処理実行
  const result = await executePayment(data);

  // 結果をキャッシュ（24時間保持）
  await redis.setex(`idempotency:${key}`, 86400, JSON.stringify(result));

  return result;
}
```

### 3.2 データベースレベルの重複防止

```sql
-- ユニーク制約
ALTER TABLE transactions ADD CONSTRAINT unique_idempotency_key
  UNIQUE (idempotency_key);

-- 挿入時
INSERT INTO transactions (id, idempotency_key, amount, ...)
VALUES (..., 'key-123', 1000, ...)
ON CONFLICT (idempotency_key) DO NOTHING
RETURNING *;
```

### 3.3 チェックリスト

| 項目                   | 必須 | 備考                  |
| ---------------------- | ---- | --------------------- |
| べき等性キーの受け入れ | ✅   | APIヘッダーで受け取る |
| 重複リクエストの検出   | ✅   | Redis/DBでチェック    |
| 前回結果の返却         | ✅   | 同じ結果を返す        |
| キーの有効期限設定     | ✅   | 24時間〜7日程度       |
| DBユニーク制約         | ✅   | 最終防衛線            |

---

## 4. セッション管理強化

### 4.1 セッション固定攻撃対策

```typescript
// ログイン成功時にセッションIDを再生成
async function login(credentials: Credentials) {
  const user = await authenticate(credentials);

  // 古いセッションを破棄
  await session.destroy();

  // 新しいセッションを作成
  await session.regenerate();
  session.userId = user.id;

  return user;
}
```

### 4.2 同時ログイン制御

```typescript
// ログイン時に既存セッションを無効化
async function login(userId: string) {
  // 既存のセッションをすべて無効化
  await redis.del(`sessions:user:${userId}:*`);

  // 新しいセッションを作成
  const sessionId = crypto.randomUUID();
  await redis.setex(`sessions:user:${userId}:${sessionId}`, 3600, 'active');

  return sessionId;
}

// または、最大セッション数を制限
async function enforceSessionLimit(userId: string, maxSessions = 3) {
  const sessions = await redis.keys(`sessions:user:${userId}:*`);
  if (sessions.length >= maxSessions) {
    // 最も古いセッションを削除
    await redis.del(sessions[0]);
  }
}
```

### 4.3 高リスク操作時の再認証

```typescript
// 送金、パスワード変更等の前に再認証を要求
async function transferMoney(userId: string, data: TransferData) {
  const lastAuth = await getLastAuthTime(userId);
  const now = Date.now();

  // 5分以内に認証していない場合は再認証を要求
  if (now - lastAuth > 5 * 60 * 1000) {
    throw new ReauthenticationRequired('高リスク操作のため再認証が必要です');
  }

  return executeTransfer(data);
}
```

### 4.4 チェックリスト

| 項目                           | 必須 | 備考                     |
| ------------------------------ | ---- | ------------------------ |
| ログイン時のセッションID再生成 | ✅   | 固定攻撃対策             |
| セッションの有効期限設定       | ✅   | 1時間〜24時間            |
| 同時ログイン制御               | 推奨 | 最大3-5セッション        |
| 高リスク操作の再認証           | ✅   | 送金、設定変更等         |
| セッションハイジャック検出     | 推奨 | IPアドレス、UA変化の検知 |

---

## 5. 監査ログ

### 5.1 記録すべき項目

| 項目           | 例                        |
| -------------- | ------------------------- |
| タイムスタンプ | 2024-01-15T10:30:00.000Z  |
| ユーザーID     | user_123                  |
| アクション     | TRANSFER, WITHDRAW, LOGIN |
| 対象リソース   | account_456               |
| 変更前の値     | { balance: 10000 }        |
| 変更後の値     | { balance: 9000 }         |
| IPアドレス     | 192.168.1.1               |
| 結果           | SUCCESS, FAILED, DENIED   |
| 失敗理由       | INSUFFICIENT_BALANCE      |

### 5.2 実装例

```typescript
async function auditLog(entry: AuditEntry) {
  await prisma.auditLog.create({
    data: {
      timestamp: new Date(),
      userId: entry.userId,
      action: entry.action,
      resourceType: entry.resourceType,
      resourceId: entry.resourceId,
      beforeValue: entry.before ? JSON.stringify(entry.before) : null,
      afterValue: entry.after ? JSON.stringify(entry.after) : null,
      ipAddress: entry.ipAddress,
      userAgent: entry.userAgent,
      result: entry.result,
      errorCode: entry.errorCode,
    },
  });
}
```

### 5.3 チェックリスト

| 項目                 | 必須 | 備考                |
| -------------------- | ---- | ------------------- |
| 全金融操作のログ記録 | ✅   | 送金、残高変更等    |
| 変更前後の値を記録   | ✅   | 追跡可能性          |
| ログの改ざん防止     | ✅   | 別DBまたは追記のみ  |
| ログの保持期間設定   | ✅   | 法令に準拠（7年等） |

---

## 6. エラーハンドリング

### 6.1 安全なエラーレスポンス

```typescript
// ❌ 悪い例: 内部情報の漏洩
throw new Error(`User ${userId} has insufficient balance: ${balance} < ${amount}`);

// ✅ 良い例: 一般的なエラーメッセージ
throw new ApplicationError('INSUFFICIENT_BALANCE', '残高が不足しています');
```

### 6.2 トランザクション失敗時のリカバリ

```typescript
async function safeTransfer(data: TransferData) {
  const txId = crypto.randomUUID();

  try {
    // 1. 送金トランザクションを記録（PENDING）
    await recordTransaction(txId, data, 'PENDING');

    // 2. 送金処理
    await executeTransfer(data);

    // 3. ステータス更新（COMPLETED）
    await updateTransactionStatus(txId, 'COMPLETED');
  } catch (error) {
    // 失敗時はステータスを更新（FAILED）
    await updateTransactionStatus(txId, 'FAILED', error.message);

    // 補償トランザクションが必要な場合
    await compensate(txId, data);

    throw error;
  }
}
```

---

## まとめ: 必須チェック項目

| カテゴリ             | 必須項目                        |
| -------------------- | ------------------------------- |
| レースコンディション | 楽観的/悲観的ロック、並行テスト |
| トランザクション     | 分離レベル、アトミック操作      |
| べき等性             | べき等性キー、重複防止          |
| セッション           | 再生成、有効期限、再認証        |
| 監査ログ             | 全操作記録、改ざん防止          |
| エラー処理           | 情報漏洩防止、リカバリ          |
