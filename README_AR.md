# ClosePilot — Smart Background Process Manager

تطبيق Windows بواجهة Flutter يعمل محليا بدون اشتراك او اتصال بالانترنت، مع مراقب PowerShell منفصل يستمر حتى بعد اغلاق الواجهة

## الوظائف

- Dashboard بتصميم Dark Premium ولمسة teal `#099999`
- مراقبة Chrome وClaude وChatGPT بشكل افتراضي
- Steam وTeams وEdge غير مفعلين افتراضيا لحماية التحميلات والمكالمات
- مفتاح تشغيل لكل برنامج، واضافة قواعد جديدة باسم العملية `*.exe`
- ايقاف تلقائي بعد 20 ثانية من اغلاق اخر نافذة مرئية (المهلة قابلة للتغيير)
- الايقاف لا يحدث الا عندما يكون المراقب قد رأى نافذة مرئية للتطبيق اولا
- Pause / Resume، تشغيل تلقائي عند الدخول لويندوز، سجل محلي JSONL، مراقبة العمليات والذاكرة الحالية
- يتجاهل العملية التي انتهت لحالها بدل تسجيل خطأ `Cannot find a process`
- مراقب منفصل عن Flutter GUI ولا يحتاج Administrator

## البناء على Windows

يحتاج Flutter SDK وVisual Studio مع `Desktop development with C++` (ليس VS Code وحده)

1. فك ضغط ملفات `ClosePilot-Source.zip` داخل مجلد عادي مثل `C:\ClosePilot`
2. افتح PowerShell داخل المجلد
3. شغل:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Build-Windows.ps1"
```

4. بعد نجاح البناء تجد `ClosePilot-Windows-Release.zip`
5. فك ضغط **كل** محتويات ملف الاصدار وشغل `ClosePilot.exe`

**مهم:** برنامج Flutter على ويندوز ليس EXE منفردا؛ يجب ابقاء `ClosePilot.exe` وDLLs ومجلد `data` مع بعضهما. لا تنقل EXE وحده

## بناء بدون Visual Studio على جهازك

يمكن رفع ملفات المصدر الى مستودع GitHub، وتشغيل `Actions > Build ClosePilot Windows EXE > Run workflow` ثم تنزيل ملف artifact بعد نجاح البناء. ملف GitHub Actions مرفق في `.github/workflows/windows-release.yml` ويستخدم Windows runner للبناء

## الترقية من AutoCloseCleaner القديم

عند التشغيل الاول يقوم ClosePilot بتعطيل اختصار التشغيل القديم وإيقاف **عملية المراقب القديم فقط** اذا كانت ما زالت تعمل. لا يحذف الملفات القديمة ولا سجلها

يخزن الملفات المحلية في:

```text
%LOCALAPPDATA%\ClosePilot\
  config.json
  ClosePilot-Agent.ps1
  ClosePilot-Setup.ps1
  status.json
  events.jsonl
```

يستمر المراقب بالعمل عندما تغلق نافذة ClosePilot. لايقافه نهائيا، عطل `Start with Windows` من Settings ثم اختر `Stop monitor completely`

## السلامة والحدود

- المراقبة تعتمد نافذة علوية مرئية لها عنوان، ولا تتعامل مع النافذة المصغرة (Minimized) على انها مغلقة
- بعض التطبيقات تستخدم نافذة بلا عنوان او خدمات منفصلة؛ وقتها قد لا يتعرف المراقب عليها ولا يوقفها، وهذا افضل من الايقاف العشوائي
- لا يقتل تطبيقات لا تظهر نافذتها للمراقب اثناء فترة عمله. العمليات القديمة التي تعمل في الخلفية فقط تترك دون تدخل
- استهلاك Working Set المعروض مجموع تقريبي، وليس RAM تم تحريرها بشكل مباشر
- يمكن ان تؤدي عملية Force Stop الى ايقاف تحميل او مكالمة او مهمة في الخلفية؛ اترك التطبيقات الحساسة غير مفعلة
- لا يوقف الخدمات الاساسية للنظام، ولا يتيح اضافتها كقواعد جديدة عبر الواجهة
- لم يتم تجميع نسخة Windows في بيئة تطوير هذه المحادثة، لذلك يلزم اختبار البناء والوظائف عمليا على Windows قبل استخدامها في عمل حساس

## اختبار الوظيفة

1. افتح Claude ثم اتركه حتى يظهر كـ `Window open` في ClosePilot
2. اغلق آخر نافذة لClaude، وانتظر مهلة الاغلاق
3. يظهر حدث `Stopped Claude ...` في Activity log اذا بقيت عمليات خلفية
4. افتح Windows Task Manager للتأكد من عدم بقاء عمليات Claude
5. كرر ذلك مع Chrome بعد حفظ العمل وايقاف التحميلات
