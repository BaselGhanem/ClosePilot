## ClosePilot v1.2.0 — نظام التحديثات

- عندما تفتح ClosePilot، يفحص فقط في بداية التشغيل آخر إصدار منشور في المستودع العام **BaselGhanem/ClosePilot-Releases**
- يوجد زر **Check for Updates** في Settings للفحص في اي وقت
- لا يتم تنزيل اي تحديث الا عندما توافق صراحة على **Update Now**
- يفحص التطبيق SHA-256 للملف الكامل قبل تمريره لعملية التثبيت
- يتم تجهيز النسخة الجديدة في مجلد مؤقت ثم يغلق البرنامج واجهته فقط (لا يوقف محرك المراقبة)، ويستبدل مجلد التشغيل مع الاحتفاظ بمجلد نسخة احتياطية من الاصدار السابق، ويعيد فتح ClosePilot
- config.json و events.jsonl وسائر البيانات محفوظة خارج مجلد التشغيل في **%LOCALAPPDATA%\\ClosePilot** ولا تتأثر بالتحديث
- عند فشل التشغيل او الاستبدال، يكتب محدّث Windows تفاصيله في **%LOCALAPPDATA%\\ClosePilot\\update.log**. عند فشل بدء EXE الجديد، يحاول استعادة النسخة السابقة
- الملفات العامة هي حزمة Windows وملف SHA-256 فقط؛ يبقى المستودع الاصلي خاصا

### تفعيل نشر التحديثات العامة (خطوات لمرة واحدة)

**1.** انشئ مستودعا جديدا في حساب GitHub: **BaselGhanem/ClosePilot-Releases**، واختر **Public** مع خيار **Add a README**. لا ترفع اليه كود Dart او ملفات المشروع الخاص.

**2.** من GitHub افتح **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**. اختر مالك الحساب BaselGhanem، و**Only select repositories** ثم المستودع العام **ClosePilot-Releases** حصرا، وامنح **Repository permissions → Contents: Read and write**. لا تمنح صلاحيات اوسع. اختر فترة صلاحية مناسبة واحتفظ بالتوكن في مكان امن.

**3.** افتح المستودع الخاص **BaselGhanem/ClosePilot → Settings → Secrets and variables → Actions → New repository secret**، ثم اضف التوكن باسم **CLOSEPILOT_RELEASE_TOKEN**. لا تنسخه الى ملفات المشروع او المحادثات.

**4.** افتح **Actions** في المستودع الخاص، ثم workflow **Publish verified public ClosePilot release**، واضغط **Run workflow** على branch **main**. سيبني Windows، ويشغّل الاختبارات، وينشر الاصدار الموافق لرقم `version` في `pubspec.yaml` الى المستودع العام، باسم **ClosePilot-Windows.zip** مع **ClosePilot-Windows.zip.sha256**.

**5.** للاصدارات القادمة، عدّل رقم الاصدار في `pubspec.yaml` وفي `lib/update_service.dart`، وحدّث `RELEASE_NOTES.md`، ثم نفذ workflow نفسه او ادفع tag مطابقا مثل `v1.3.0` الى المستودع الخاص. لا تعيد نشر اصدار موجود بالرقم ذاته.

**حدود حالية:** لا يمكن للتطبيق الموجود اصلا قبل v1.2.0 تحديث نفسه؛ يلزم تنزيل v1.2.0 يدويا مرة اخيرة. لا يمكن اختبار وصول الاشعارات من GitHub Releases قبل انشاء المستودع العام ونشر اول اصدار عليه.

# ClosePilot — Smart Background Process Manager

تطبيق Windows بواجهة Flutter يعمل محليا بدون اشتراك او اتصال بالانترنت، مع مراقب PowerShell منفصل يستمر حتى بعد اغلاق الواجهة

## Basel Edition v1.1.0 — الجديد

- **Run in background**: زر مباشر لاخفاء نافذة Flutter وتشغيلها ضمن Windows system tray. اضغط على ايقونة ClosePilot بجانب الساعة لاسترجاع الواجهة، او استخدم Right click > Open ClosePilot
- خيار **Minimize to system tray** في Settings مفعل افتراضيا، بحيث اغلاق نافذة ClosePilot يخفي الواجهة دون ايقاف المراقب
- **Startup اسرع**: عرض لوحة التحكم مباشرة، مع خط تحميل رفيع اثناء تجهيز المراقب بدل حجب الواجهة
- واجهة Basel Edition بتوقيع BG، الوان teal، ومؤشرات بتصميم اعلى وضوحا
- **Time saved**: تقدير شفاف وليس وقتا مقاسا. الافتراضي 20 ثانية لكل عملية تنظيف تلقائي مكتملة لتطبيق واحد، وقابل للتغيير من Settings. يسجل التطبيق العدد من events.jsonl، بما في ذلك وقت عمل المراقب بدون الواجهة
- رسم نشاط اخر 7 ايام، وعدد جلسات التنظيف التلقائي، وعدد عمليات Close All اليدوية
- **CLOSE ALL**: يطلب منك تحديد التطبيقات، ويغلق عملياتها بالقوة حتى لو كانت نوافذها مفتوحة. التطبيقات غير المفعلة للمراقبة التلقائية لا تكون مختارة افتراضيا، لكن يمكن اختيارها يدويا او Select all. العملية قد تفقد العمل غير المحفوظ او توقف المكالمات والتحميلات؛ توجد شاشة تاكيد قبل التنفيذ
- سجل Activity log يميز بين توقفات العمليات والتنظيف التلقائي وجلسات Close All اليدوية
- حماية اضافية تمنع استخدام Close All لايقاف العمليات الحيوية في Windows حتى لو عدل شخص ملف الاعدادات يدويا
- يحافظ على ملفات الاعدادات والسجلات السابقة في %LOCALAPPDATA%\\ClosePilot

**مهم:** عند ترقية نسخة موجودة، يتم تحديث المراقب من الاصدار 1.0.1 الى 1.1.0 تلقائيا. المتغيرات الجديدة لها قيم افتراضية مع الحفاظ على قواعد التطبيقات السابقة.

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
