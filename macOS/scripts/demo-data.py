"""Writes StockBar's demo account: a made-up portfolio (stocks at real past closes, bonds from real banks, public
funds), expense categories and two years of transactions. Everything is invented; nothing comes from a real account.

Run from the macOS folder:  python3 scripts/demo-data.py Resources/Demo
The transactions end on `today` below; the app moves them forward to the current month when it seeds the demo
(see DataAccount.swift), so the data doesn't need regenerating to stay current."""
import json, os, random, sys, time, urllib.request, uuid
from datetime import date, datetime, timedelta, timezone

out = sys.argv[1]
random.seed(7)
today = date(2026, 10, 29)
os.makedirs(out, exist_ok=True)

def uid(): return str(uuid.UUID(int=random.getrandbits(128))).upper()
def iso(d): return datetime(d.year, d.month, d.day, 15, 0, tzinfo=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
def daykey(d): return d.year * 10000 + d.month * 100 + d.day

# --- Stocks: buys on made-up dates at that day's real close (Yahoo), so average prices are plausible -------------
def closes(symbol, start, end):
    url = f"https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?period1={int(time.mktime(start.timetuple()))}&period2={int(time.mktime(end.timetuple()))}&interval=1d"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    r = json.load(urllib.request.urlopen(req, timeout=30))["chart"]["result"][0]
    return {datetime.fromtimestamp(t, timezone.utc).date(): c for t, c in zip(r["timestamp"], r["indicators"]["quote"][0]["close"]) if c}

positions = [  # ticker, Yahoo symbol, [(buy date, quantity)]
    ("WEGE3", "WEGE3.SA", [(date(2024, 3, 12), 300), (date(2025, 6, 3), 200)]),
    ("EGIE3", "EGIE3.SA", [(date(2024, 5, 20), 400)]),
    ("TAEE11", "TAEE11.SA", [(date(2024, 8, 6), 500), (date(2025, 9, 15), 300)]),
    ("BBSE3", "BBSE3.SA", [(date(2024, 11, 4), 600)]),
    ("PRIO3", "PRIO3.SA", [(date(2025, 2, 11), 350)]),
    ("VIVT3", "VIVT3.SA", [(date(2025, 4, 22), 250)]),
    ("HGLG11", "HGLG11.SA", [(date(2024, 2, 14), 60), (date(2025, 7, 9), 40)]),
    ("KNRI11", "KNRI11.SA", [(date(2024, 9, 18), 80)]),
    ("XPML11", "XPML11.SA", [(date(2025, 1, 21), 120)]),
    ("BOVA11", "BOVA11.SA", [(date(2024, 6, 10), 150)]),
    ("IVVB11", "IVVB11.SA", [(date(2024, 4, 2), 90), (date(2025, 10, 1), 50)]),
    ("AAPL", "AAPL", [(date(2024, 7, 15), 25)]),
    ("MSFT", "MSFT", [(date(2025, 3, 3), 12)]),
    ("NVDA", "NVDA", [(date(2025, 5, 12), 40)]),
]
trades = []
for ticker, symbol, buys in positions:
    history = closes(symbol, min(d for d, _ in buys) - timedelta(days=10), max(d for d, _ in buys) + timedelta(days=5))
    for d, q in buys:
        price = next(history[x] for x in sorted(history) if x >= d)
        trades.append({"id": uid(), "ticker": ticker, "kind": "buy", "date": iso(d), "quantity": q, "price": round(price, 2)})
trades.sort(key=lambda t: t["date"])
json.dump(trades, open(f"{out}/trades.json", "w"), indent=2)

alerts = [{"id": uid(), "ticker": "PRIO3", "target": 40.0, "kind": "buy", "isEnabled": True},
          {"id": uid(), "ticker": "WEGE3", "target": 60.0, "kind": "sell", "isEnabled": True}]
json.dump(alerts, open(f"{out}/alerts.json", "w"), indent=2)

# --- Bonds: real banks (their public CNPJs, so the FGC Watcher can group them), made-up positions ------------------
bonds = [
    ("CDB", "BANCO INTER S.A.", "00416968000101", "fixed", 13.2, date(2025, 1, 10), date(2028, 1, 10), 40),
    ("CDB", "BANCO DAYCOVAL S.A.", "62232889000190", "cdi", 112.0, date(2024, 8, 5), date(2027, 8, 5), 35),
    ("LCA", "BANCO BTG PACTUAL S.A.", "30306294000145", "cdi", 94.0, date(2025, 3, 18), date(2027, 3, 18), 30),
    ("CDB", "BANCO PAN S.A.", "59285411000113", "ipca", 7.1, date(2024, 11, 22), date(2029, 11, 22), 25),
    ("CDB", "BANCO ABC BRASIL S.A.", "28195667000106", "fixed", 14.05, date(2025, 6, 2), date(2030, 6, 2), 20),
    ("LCI", "BANCO INTER S.A.", "00416968000101", "cdi", 93.0, date(2025, 8, 14), date(2027, 8, 14), 15),
]
json.dump([{"id": uid(), "kind": k, "issuer": issuer, "issuerCNPJ": cnpj, "code": f"{k}{random.randrange(10**7, 10**8)}{random.choice('ABCDEFGHJK')}",
            "issueDay": daykey(issued), "maturityDay": daykey(matures), "indexer": indexer, "rate": rate, "quantity": q, "unitPrice": 1000}
           for k, issuer, cnpj, indexer, rate, issued, matures, q in bonds],
          open(f"{out}/bonds.json", "w"), indent=2)

# --- Funds: well-known public funds (CVM data), made-up share counts --------------------------------------------------
funds = [
    ("45278833000157", "TREND DI FIC FI RENDA FIXA SIMPLES", 18000.0, False, "selic"),
    ("09215250000113", "BTG PACTUAL TESOURO SELIC FI RENDA FIXA REFERENCIADO DI", 4200.0, False, "selic"),
    ("14188162000100", "SPARTA TOP FIC FIF RENDA FIXA CRÉDITO PRIVADO", 9500.0, False, "credit"),
    ("23556185000110", "AZ QUEST LUCE FIC FIF RENDA FIXA CRÉDITO PRIVADO", 11000.0, False, "credit"),
    ("42730834000100", "SPARTA INFRA FIC FI INCENTIVADO INFRAESTRUTURA", 160.0, True, "infrastructure"),
]
json.dump([{"id": uid(), "cnpj": c, "name": n, "kind": "fif", "quantity": q, "taxExempt": te, "purpose": p} for c, n, q, te, p in funds],
          open(f"{out}/fund-holdings.json", "w"), indent=2)

# --- Expense categories with limits (the app's starting set, in English) ----------------------------------------------
categories = [
    ("Groceries & Cleaning", "cart", 1800, ["groceries", "supermarket"]),
    ("Home & Furniture", "house", None, ["home", "furniture", "houseware", "housing improvement"]),
    ("Delivery & Restaurants", "fork.knife", 1200, ["eating out", "restaurant", "food delivery", "delivery", "food and drinks"]),
    ("Transport & Travel", "car", 700, ["transport", "taxi", "ride", "gas station", "parking", "travel", "airline", "accommodation", "toll"]),
    ("Health & Pharmacy", "cross.case", 500, ["health", "pharmacy", "hospital", "dentist", "medical"]),
    ("Beauty & Self-care", "sparkles", 300, ["beauty", "wellness", "gym", "fitness"]),
    ("Electronics & Tech", "laptopcomputer", None, ["electronics", "technology"]),
    ("Subscriptions & Apps", "arrow.triangle.2.circlepath", 200, ["subscription", "streaming", "digital services", "software"]),
    ("Books & Education", "book", 400, ["education", "books", "school", "university"]),
    ("Pets", "pawprint", 350, ["pet"]),
    ("Clothing & Accessories", "tshirt", 500, ["clothing", "apparel", "fashion"]),
    ("Leisure & Games", "gamecontroller", 400, ["leisure", "entertainment", "games", "gaming", "cinema", "tickets"]),
    ("Housing & Bills", "bolt", 2200, ["bills", "utilities", "electricity", "water", "rent", "telecommunications", "internet", "mobile", "taxes", "housing"]),
    ("PIX & Transfers", "arrow.left.arrow.right", None, ["transfer", "pix"]),
    ("Shopping", "bag", 800, ["shopping", "online shopping", "department store"]),
]
json.dump({"categories": [{"id": uid(), "name": n, "symbol": s, **({"limit": l} if l else {}), "pluggyKeywords": k} for n, s, l, k in categories],
           "rules": {}, "overrides": {}, "manual": [], "totalLimit": 11000, "alertAt": 0.8, "notified": []},
          open(f"{out}/expenses.json", "w"), indent=2)

# --- Two years of transactions: a credit card and a checking account ---------------------------------------------------
CARD, BANK = uid(), uid()
accounts = [{"id": CARD, "itemId": uid(), "type": "CREDIT", "subtype": "CREDIT_CARD", "name": "Nubank Ultravioleta", "number": "4321", "balance": 0, "currencyCode": "BRL"},
            {"id": BANK, "itemId": uid(), "type": "BANK", "subtype": "CHECKING_ACCOUNT", "name": "Banco Inter", "number": "12345-6", "balance": 18450.32, "currencyCode": "BRL"}]

# merchant, Pluggy category, (min, max), times a month
card_merchants = [
    ("PAO DE ACUCAR", "Groceries", (90, 420), 4), ("CARREFOUR", "Groceries", (150, 520), 2), ("HORTIFRUTI", "Groceries", (40, 140), 2),
    ("IFOOD", "Food delivery", (35, 120), 7), ("OUTBACK STEAKHOUSE", "Eating out", (150, 320), 1), ("STARBUCKS", "Eating out", (18, 45), 3),
    ("MADERO", "Eating out", (90, 210), 1), ("UBER", "Taxi and ride-hailing", (14, 48), 6), ("99APP", "Taxi and ride-hailing", (12, 35), 2),
    ("SHELL SELECT", "Gas stations", (180, 320), 2), ("DROGASIL", "Pharmacy", (30, 160), 2), ("DROGA RAIA", "Pharmacy", (25, 110), 1),
    ("NETFLIX.COM", "Digital services", (55.90, 55.90), 1), ("SPOTIFY", "Digital services", (34.90, 34.90), 1),
    ("AMAZON PRIME", "Digital services", (19.90, 19.90), 1), ("AMAZON.COM.BR", "Online shopping", (60, 380), 2),
    ("MERCADO LIVRE", "Online shopping", (45, 300), 1), ("CINEMARK", "Leisure", (40, 120), 1), ("SMART FIT", "Gyms and fitness centers", (129.90, 129.90), 1),
    ("PETZ", "Pet supplies", (80, 260), 1), ("RENNER", "Clothing", (90, 350), 0.5), ("LIVRARIA CULTURA", "Bookstore", (50, 140), 0.5),
]
bank_bills = [("ENEL DISTRIBUICAO", "Electricity", (180, 340), "DEBITO AUTOMATICO ENEL", None),
              ("VIVO FIBRA", "Internet", (129.90, 129.90), "DEBITO AUTOMATICO VIVO", None),
              ("CONDOMINIO RESIDENCIAL JARDINS", "Housing", (1250, 1250), "PAGAMENTO DE BOLETO CONDOMINIO", "BOLETO"),
              ("SABESP", "Water", (70, 140), "DEBITO AUTOMATICO SABESP", None)]
people = ["Ana Souza", "Carlos Lima"]

months, fetched = {}, {}
first = date(2024, 11, 1)
ref = datetime(2001, 1, 1, tzinfo=timezone.utc)
# Stamped a month ahead, so the app never finds a month stale and tries to sync it.
stamp = (datetime.now(timezone.utc) + timedelta(days=30) - ref).total_seconds()
m = first
while m <= today.replace(day=1):
    key = m.year * 100 + m.month
    last = (date(m.year + (m.month == 12), m.month % 12 + 1, 1) - timedelta(days=1)).day
    end_day = today.day if (m.year, m.month) == (today.year, today.month) else last
    txs = []
    def add(d, desc, amount, account, ttype, category, method=None, receiver=None, payer=None, card_meta=None):
        t = {"id": uid(), "accountId": account, "description": desc, "descriptionRaw": desc, "amount": round(amount, 2), "currencyCode": "BRL",
             "date": iso(d), "type": ttype, "category": category, "status": "POSTED"}
        if account == CARD or category not in ("Transfer - PIX", "Salary", "Credit card payment"):
            t["merchant"] = {"businessName": desc, "category": category}
        if method or receiver or payer:
            t["paymentData"] = {"paymentMethod": method, **({"receiver": {"name": receiver}} if receiver else {}), **({"payer": {"name": payer}} if payer else {})}
        if card_meta: t["creditCardMetadata"] = card_meta
        txs.append(t)
    for name, cat, (lo, hi), per_month in card_merchants:
        count = int(per_month) + (random.random() < per_month % 1 if per_month % 1 else 0) + (random.random() < 0.3 and per_month >= 2)
        if name == "IFOOD" and m.month in (12, 1, 7): count += 3  # holidays
        for _ in range(count):
            d = date(m.year, m.month, random.randint(1, end_day))
            add(d, name, random.uniform(lo, hi), CARD, "DEBIT", cat)
    for name, cat, (lo, hi), desc, method in bank_bills:
        if end_day >= 10:
            add(date(m.year, m.month, 10), desc, -random.uniform(lo, hi), BANK, "DEBIT", cat, method=method)
    if end_day >= 5:
        add(date(m.year, m.month, 5), "SALARIO ACME TECNOLOGIA LTDA", 14500.0, BANK, "CREDIT", "Salary", method="TED")
        add(date(m.year, m.month, 5), "PAGAMENTO FATURA NUBANK", -random.uniform(5200, 7600), BANK, "DEBIT", "Credit card payment")
    for _ in range(random.randint(1, 3)):
        d = date(m.year, m.month, random.randint(1, end_day))
        p = random.choice(people)
        add(d, f"PIX ENVIADO {p.upper()}", -random.uniform(40, 350), BANK, "DEBIT", "Transfer - PIX", method="PIX", receiver=p)
    if random.random() < 0.4:
        d = date(m.year, m.month, random.randint(1, end_day))
        add(d, "PIX RECEBIDO ANA SOUZA", random.uniform(50, 200), BANK, "CREDIT", "Transfer - PIX", method="PIX", payer="Ana Souza")
    if key == 202606:  # a phone in 10 installments: cards send every installment with the purchase
        for n in range(1, 11):
            add(date(2026, 6, 14), "APPLE STORE", 899.0, CARD, "DEBIT", "Electronics",
                card_meta={"installmentNumber": n, "totalInstallments": 10, "totalAmount": 8990.0, "purchaseDate": iso(date(2026, 6, 14))})
    if key == 202601:
        add(date(2026, 1, 18), "LATAM AIRLINES", 2380.0, CARD, "DEBIT", "Airlines")
    months[str(key)] = sorted(txs, key=lambda t: t["date"])
    fetched[str(key)] = stamp
    m = date(m.year + (m.month == 12), m.month % 12 + 1, 1)

json.dump({"months": months, "fetchedAt": fetched, "accounts": accounts, "currencyRead": [int(k) for k in months]},
          open(f"{out}/transactions-by-month.json", "w"))
print(f"{len(trades)} trades, {len(bonds)} bonds, {len(funds)} funds, {sum(len(v) for v in months.values())} transactions in {len(months)} months")
