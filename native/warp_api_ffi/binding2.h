typedef char int8_t;
typedef long long int int64_t;
typedef long long int uint64_t;
typedef long long int uintptr_t;
typedef long int uint32_t;
typedef char bool;
typedef void *DartPostCObjectFnType;

typedef struct WalletBalance {
  uint64_t confirmed;
  int64_t unconfirmed;
  uint64_t spendable;
} WalletBalance;
