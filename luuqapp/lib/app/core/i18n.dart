part of '../../main.dart';

String tr(String trText, String enText) {
  return appLanguageNotifier.value == AppLanguage.tr ? trText : enText;
}

const Map<String, String> _menuDict = {
  'Hafif': 'Light',
  'Güçlü': 'Strong',
  'Ferah': 'Fresh',
  'Tatlı': 'Sweet',
  'Sıcak': 'Warm',
  'Eğlenceli': 'Fun',
  'Dingin': 'Calm',
  'Dengeli': 'Balanced',
  'Filtre Kahve': 'Filter Coffee',
  'Espresso': 'Espresso',
  'Türk Kahvesi': 'Turkish Coffee',
  'Sıcak Çikolata': 'Hot Chocolate',
  'Soğuk Kahve': 'Iced Coffee',
  'Çay': 'Tea',
  'Limonata': 'Lemonade',
  'Meyve Suyu': 'Fruit Juice',
  'Pasta': 'Cake',
  'Kurabiye': 'Cookie',
  'Kek': 'Muffin',
  'Tiramisu': 'Tiramisu',
  'San Sebastian': 'San Sebastian',
  'Kruvasan': 'Croissant',
  'Sandviç': 'Sandwich',
  'Tost': 'Toast',
  'İçecekler': 'Drinks',
  'Tatlılar': 'Desserts',
  'Tüm Modlar': 'All Moods',
  'İçecek': 'Drink',
  'Tümü': 'All',
  // Category names
  'Espresso Kahveler': 'Espresso Coffees',
  'Filtre Kahveler': 'Filter Coffees',
  'Sıcak İçecekler': 'Hot Drinks',
  'Ice Kahveler': 'Iced Coffees',
  'LUUQ Kokteyl': 'LUUQ Cocktail',
  'Bitki Çayları': 'Herbal Teas',
  'Meşrubatlar': 'Soft Drinks',
  'Pasta & Tatlı': 'Pastry & Dessert',
  'LUUQ Chocolate': 'LUUQ Chocolate',
  'Termos & Seramik': 'Thermos & Ceramic',
  'Dondurmalar': 'Ice Creams',
  'Ekstralar': 'Extras',
  // Category descriptions
  'Yoğun, klasik ve taze espresso bazlı favoriler.':
      'Intense, classic and fresh espresso-based favorites.',
  'Özenle seçilmiş yöresel çekirdekler ve özel demlemeler.':
      'Carefully selected regional beans and special brews.',
  'İçinizi ısıtacak geleneksel ve modern sıcak lezzetler.':
      'Traditional and modern hot flavors to warm you up.',
  'Günün her saati ferahlık veren buzlu kahve alternatifleri.':
      'Refreshing iced coffee alternatives for any time of day.',
  'LUUQ imzalı alkolsüz, ferahlatıcı ve özel reçeteli karışımlar.':
      'LUUQ signature non-alcoholic, refreshing special blends.',
  'Doğadan gelen rahatlatıcı ve canlandırıcı özel bitki harmanları.':
      'Relaxing and invigorating herbal blends from nature.',
  'Taze meyvelerle hazırlanan buzlu yaz şölenleri.':
      'Frozen summer treats made with fresh fruits.',
  'Patlayan boba incileriyle dolu eğlenceli ve serinletici lezzetler.':
      'Fun and refreshing flavors full of popping boba pearls.',
  'Kıvamlı, yoğun ve tatlı krizlerine birebir sütlü serinlik.':
      'Thick, creamy milkshakes for your sweet cravings.',
  'Yaz aylarının en serinletici ve leziz dondurma çeşitleri.': 'The most refreshing and delicious ice cream varieties of the summer months.',
  'Klasik gazozlar, doğal sodalar ve enerji veren içecekler.':
      'Classic sodas, natural sparkling waters and energy drinks.',
  'Kahvenize mükemmel eşlik edecek taptaze, el yapımı tatlılar.':
      'Freshly made, handcrafted desserts to pair with your coffee.',
  'LUUQ ustalarından özel yapım premium artizan çikolatalar.':
      'Premium artisan chocolates handcrafted by LUUQ masters.',
  'Taze ekmeklerle hazırlanan, doyurucu ve leziz atıştırmalıklar.':
      'Satisfying and delicious snacks made with fresh bread.',
  'LUUQ deneyimini gittiğiniz her yere taşıyacak şık tasarımlar.':
      'Stylish designs to carry the LUUQ experience everywhere.',
  'İçeceğinizi tamamen kişiselleştirebileceğiniz ekstra dokunuşlar.':
      'Extra touches to fully customize your drink.',
  'Vanilya': 'Vanilla',
  'Kakao': 'Cocoa',
  'Karamel': 'Caramel',
  'Antep Fıstığı': 'Pistachio',
  'Limon': 'Lemon',
  'Kavun': 'Melon',
  'Çilek': 'Strawberry',
  'Karadut': 'Black Mulberry',
  'Bal Badem': 'Honey Almond',
  'Bubble Gum': 'Bubble Gum',
  'Blue Sky': 'Blue Sky',
  'Meyve Şöleni': 'Fruit Feast',
  'Oreo': 'Oreo',
  'Klasik ve yoğun gerçek vanilya çekirdeği lezzeti.':
      'Classic and intense real vanilla bean flavor.',
  'Yoğun çikolata dolgulu geleneksel kakao keyfi.':
      'Traditional cocoa treat with intense chocolate flavor.',
  'Karamel soslu tatlı ve kremamsı dondurma.':
      'Sweet and creamy ice cream with caramel sauce.',
  'Taze Antep fıstığı parçacıklarıyla zenginleşen lezzet.':
      'Flavor enriched with fresh pistachio pieces.',
  'Ekşi ve ferahlatıcı gerçek limon aroması.':
      'Tart and refreshing real lemon flavor.',
  'Yaz kavununun tatlı ve sulu serinliği.':
      'Sweet and juicy coolness of summer melon.',
  'Taze yaz çilekleriyle hazırlanan meyveli dondurma.':
      'Fruit ice cream prepared with fresh summer strawberries.',
  'Doğal karadut taneleriyle tatlı-ekşi ferahlık.':
      'Sweet-sour refreshment with natural black mulberry grains.',
  'Süzme bal ve çıtır badem parçacıklarının uyumu.':
      'Harmony of strained honey and crunchy almond pieces.',
  'Eğlenceli sakız aromalı çocuksu tat.':
      'Playful bubble gum flavored childhood treat.',
  'Farklı ve özel aromasıyla gökyüzü mavisi lezzet.':
      'Sky blue flavor with a unique and special aroma.',
  'Karışık yaz meyvelerinin eşsiz uyumu.':
      'Unique harmony of mixed summer fruits.',
  'Çıtır Oreo bisküvi parçacıklarıyla kremamsı dondurma.':
      'Creamy ice cream with crunchy Oreo cookie pieces.',
  // Tags
  'Popüler': 'Popular',
  'Yeni': 'New',
  'Klasik': 'Classic',
  'Soğuk': 'Cold',
  'Yazın İyisi': 'Summer Favorite',

  'Ahududu ve taze limonun canlandırıcı uyumu':
      'Refreshing harmony of raspberry and fresh lemon',
  'Ananas ve bademin hafif tatlı uyumu':
      'Lightly sweet harmony of pineapple and almond',
  'Antep fıstıklı rüya': 'Pistachio dream',
  'Ağızda patlayan şekerli eğlenceli tatlı': 'Fun dessert with popping candy',
  'Badem kremalı limonlu zarif tart':
      'Elegant tart with almond cream and lemon',
  'Baharatlı çay ve kremamsı süt': 'Spiced tea and creamy milk',
  'Bardakta taze meyveli kat kat lezzet':
      'Layered treat with fresh fruit in a glass',
  'Baskın espresso tadı ve bol köpüklü sıcak süt.':
      'Intense espresso flavor and hot milk with plenty of foam.',
  'Bağışıklık destekleyici zencefil, limon ve bal kürü':
      'Immune-boosting ginger, lemon and honey cure',
  'Beyaz çikolata sevenlere özel spesiyal':
      'Special treat for white chocolate lovers',
  'Beyaz çikolatalı latte': 'White chocolate latte',
  'Beyaz çikolatalı mocha': 'White chocolate mocha',
  'Beyaz çikolatalı süt': 'White chocolate milk',
  'Beyaz çikolatalı şelale tasarımlı pasta':
      'Cake with white chocolate waterfall design',
  'Bol Oreo bisküvili klasik peynir tatlısı':
      'Classic cheesecake with plenty of Oreo cookies',
  'Bol fıstıklı çıtır hamurlu Fransız tartı':
      'French tart with crispy pastry and lots of pistachios',
  'Buz gibi serinletici, şeftali aromalı tatlı siyah çay.':
      'Ice-cold refreshing, peach flavored sweet black tea.',
  'Buz gibi su ve yoğun espresso. Ferahlatıcı ve net.':
      'Ice-cold water and intense espresso. Refreshing and clean.',
  'Buzlu beyaz mocha': 'Iced white mocha',
  'Buzlu filtre kahve': 'Iced filter coffee',
  'Buzlu flat white': 'Iced flat white',
  'Buzlu karamel latte': 'Iced caramel latte',
  'Buzlu karamel macchiato': 'Iced caramel macchiato',
  'Buzlu matcha sütlü': 'Iced matcha latte',
  'Buzlu sade americano': 'Iced black americano',
  'Buzlu sütlü espresso': 'Iced espresso with milk',
  'Buzlu sütlü filtre': 'Iced filter coffee with milk',
  'Ananas, portakal ve limonun ferah tropikal buluşması.':
      'A refreshing tropical blend of pineapple, orange, and lemon.',
  'Buzlu çikolatalı mocha': 'Iced chocolate mocha',
  'Buzlu, karamelli ve sütlü tatlı kahve rüyası.':
      'Iced, caramel and milky sweet coffee dream.',
  'Cam şişede doğal kaynak suyu': 'Natural spring water in a glass bottle',
  'Damla sakızı aromalı sahlep': 'Sahlep flavored with mastic gum',
  'Dev çikolatalı kurabiye turtası': 'Giant chocolate cookie pie',
  'Doğa yeşili tonlarında şık termos': 'Stylish thermos in forest green tones',
  'Doğal mineralli su': 'Natural sparkling mineral water',
  'Doğal mineralli su büyük boy': 'Natural sparkling mineral water large size',
  'Egzotik baharatlı karamel rüyası': 'Exotic spiced caramel dream',
  'Yoğun mango aromasıyla egzotik ve ferah bir frozen.':
      'An exotic and refreshing frozen with intense mango aroma.',
  'Egzotik meyve karışımı': 'Exotic fruit mix',
  'Egzotik yeşil çay ve meyve harmonisi': 'Exotic green tea and fruit harmony',
  'Ekşi vişnelerle dengelenmiş tatlı tart':
      'Sweet tart balanced with sour cherries',
  'El yapımı özel seramik çay demliği': 'Handmade custom ceramic teapot',
  'Enerji veren klasik lezzet': 'Classic energizing flavor',
  'Ergonomik beyaz renkli pratik termos': 'Ergonomic white practical thermos',
  'Erimiş 4 peynirli doyurucu bagel': 'Hearty bagel with 4 melted cheeses',
  'Espresso ile ıslatılmış mascarpone peynirli klasik':
      'Classic tiramisu with espresso-soaked ladyfingers and mascarpone cheese',
  'Espresso ve az süt, sert ve yoğun':
      'Espresso and a dash of milk, strong and intense',
  'Espresso üzerine dondurma': 'Affogato - Ice cream topped with espresso',
  'Meyvemsi notalar, canlı aroma ve hafif çiçeksi bir bitiş.':
      'Fruity notes, vibrant aroma, and a light floral finish.',
  'Farklı aromalarda ekstra şurup ilavesi':
      'Extra syrup addition in different flavors',
  'Ferahlatıcı limon ve canlandırıcı zencefil':
      'Refreshing lemon and invigorating ginger',
  'Ferahlatıcı misket limonu': 'Refreshing lime',
  'Frambuaz ve beyaz çikolata': 'Raspberry and white chocolate',
  'Frambuazlı mocha': 'Raspberry mocha',
  'Fındık kreması dolgulu sıcak kruvasan':
      'Warm croissant filled with hazelnut cream',
  'Fındık ve fıstık dolgulu neşe küpleri':
      'Joy cubes filled with hazelnut and pistachio',
  'Fındıklı karışım': 'Hazelnut mix',
  'Geleneksel demlik çay': 'Traditional brewed pot tea',
  'Geleneksel kesme dondurma formunda pasta':
      'Traditional Turkish style cut ice cream cake',
  'Geleneksel köpüklü Türk kahvesi': 'Traditional frothy Turkish coffee',
  'Geleneksel tahin, karamel ve çilek füzyonu':
      'Traditional fusion of tahini, caramel and strawberry',
  'Gerçek Belçika çikolatası ilavesi': 'Real Belgian chocolate addition',
  'Gerçek çikolata parçalarıyla hazırlanan sıcak, tatlı kış klasiği.':
      'Warm, sweet winter classic prepared with real chocolate chips.',
  'Fındıksı aroma, dolgun gövde ve dengeli kahve karakteri.':
      'Nutty aroma, full body, and a balanced coffee character.',
  'Guava patlaması': 'Guava blast',
  'Günlük taze cabata ekmeğine lezzetler':
      'Flavors on daily fresh ciabatta bread',
  'Günlük taze demlenen, sade ve dengeli klasik filtre kahve.':
      'Daily fresh-brewed, plain, and balanced classic filter coffee.',
  'Günün stresini alan rahatlatıcı papatya ve melisa':
      'Relaxing chamomile and lemon balm to relieve daily stress',
  'Hafif ekşi frambuaz ve yeşil fıstık şöleni':
      'Slightly sour raspberry and green pistachio feast',
  'Haki yeşili dayanıklı çelik termos': 'Khaki green durable steel thermos',
  'Halka şeklinde badem kremalı Fransız tatlısı':
      'Ring-shaped French pastry with almond cream (Paris-Brest)',
  'Hassas mideler için laktozsuz süt alternatifi':
      'Lactose-free milk alternative for sensitive stomachs',
  'Haşhaşlı taze ekmek içinde özel peynir':
      'Special cheese in fresh poppy seed bread',
  'Hindi füme ve yeşillikli hafif öğün':
      'Light meal with smoked turkey and greens',
  'Isı yalıtımlı mat siyah çelik termos': 'Insulated matte black steel thermos',
  'Yuzu ferahlığı ve şeftali tatlılığı bir arada.':
      'Yuzu freshness and peach sweetness combined.',
  'Japon yeşil çayı ve sütün huzur veren lezzeti.':
      'The peaceful taste of Japanese green tea and milk.',
  'Kahvenize ekstra bir shot espresso':
      'An extra shot of espresso for your coffee',
  'Kahverengi tonlarında sızdırmaz termos': 'Leak-proof thermos in brown tones',
  'Karamel aromalı sütlü kahve keyfi': 'Caramel flavored milk coffee pleasure',
  'Karamel sos ve vanilyalı süt': 'Caramel sauce and vanilla milk',
  'Karamelli affogato yorumu': 'Caramel affogato twist',
  'Klasik Beyoğlu gazozu ferahlığı': 'Classic Beyoglu soda freshness',
  'Çilek aroması ve boba incileriyle tatlı, eğlenceli bir içim.':
      'A sweet and fun drink with strawberry aroma and boba pearls.',
  'Dengeli gövde, zarif asidite ve yumuşak içimli filtre kahve.':
      'Balanced body, elegant acidity, and smooth-drinking filter coffee.',
  'Krem renkli zarif çelik termos': 'Elegant cream colored steel thermos',
  'Kremamsı beyaz çikolata ve kavrulmuş fındık':
      'Creamy white chocolate and roasted hazelnuts',
  'Kremamsı süt köpüğü ile klasik İtalyan lezzeti':
      'Classic Italian taste with creamy milk foam',
  'Kuzu kulağı otlu özel tarif': 'Special recipe with sorrel herb',
  'Köpüksü hafifliğiyle yoğun çikolata':
      'Intense chocolate with foamy lightness',
  'Közlenmiş biber ve roast beef eti': 'Roasted peppers and roast beef',
  'Künefe ve fıstık dolgulu meşhur Dubai çikolatası':
      'Famous Dubai chocolate filled with kadayif and pistachio',
  'Orman meyvelerinin tatlı-ekşi ferahlığıyla hazırlanır.':
      'Prepared with the sweet and sour freshness of forest berries.',
  'Kızarmış marshmallow ve çikolatalı kupa':
      'Toasted marshmallow and hot chocolate mug',
  'Limon ferahlığıyla beyaz çikolatalı blondie':
      'White chocolate blondie with lemon freshness',
  'Limonlu soğuk kahve': 'Iced coffee with lemon',
  'Luuq ustalarından özel çikolata lokumu':
      'Special chocolate delight from LUUQ masters',
  'Yoğun mango aroması ve boba incileriyle tropik lezzet.':
      'A tropical flavor with intense mango aroma and boba pearls.',
  'Mat siyah geniş hacimli mug termos': 'Matte black large capacity travel mug',
  'Matcha karışım kokteyl': 'Matcha mix cocktail',
  'Minimal beyaz tasarımlı kompakt termos':
      'Compact thermos with minimal white design',
  'Misket limonu kremalı hafif ekler': 'Light eclairs with lime cream',
  'Modern gri tasarımlı günlük termos': 'Daily thermos with modern gray design',
  'Nane ferahlığıyla zenginleşen serin limonata keyfi.':
      'Cool lemonade pleasure enriched with mint freshness.',
  'Naneli mocha': 'Mint mocha',
  'Oreo bisküvi parçalı latte': 'Oreo biscuit chunk latte',
  'Oreo parçalı buzlu latte': 'Iced latte with Oreo pieces',
  'Orijinal Lotus bisküvi kremalı porsiyonluk ekler':
      'Individual eclairs with original Lotus biscuit cream',
  'Orijinal Nutella ile hazırlanan yoğun lezzet':
      'Intense flavor prepared with original Nutella',
  'Renk değiştiren büyüleyici kokteyl': 'Mesmerizing color-changing cocktail',
  'Reyhan aromalı efsanevi gazoz': 'Legendary sweet basil flavored soda',
  'Rose gold renkli şık çelik termos': 'Stylish steel thermos in rose gold',
  'Rubika özel mocha': 'Rubika special mocha',
  'Sade ve güçlü espresso suyla buluşur':
      'Plain and strong espresso meets water',
  'San Sebastian tarzı yanık üst kabuklu':
      'San Sebastian style burnt-top cheesecake',
  'Soğuk suda saatlerce demlenmiş, yumuşak içimli yüksek kafein.':
      'Brewed in cold water for hours, smooth taste with high caffeine.',
  'Taze filtre kahvenin sütle yumuşatılmış sıcak yorumu.':
      'Warm milk-softened version of fresh filter coffee.',
  'Tabağıyla birlikte el yapımı kahve kupası':
      'Handmade coffee mug with saucer',
  'Tam tahıllı ekmek, ezine peyniri ve domates':
      'Whole grain bread, ezine cheese and tomato',
  'Taptaze meyveler ve boba incileriyle ferah bir bubble tea.':
      'A refreshing bubble tea with fresh fruits and boba pearls.',
  'Tarçın aromalı geleneksel sahlep': 'Traditional sahlep with cinnamon aroma',
  'Tarçın ve karamelize elmalı çıtır tart':
      'Crispy tart with cinnamon and caramelized apple',
  'Tatlı ekşi karışım': 'Sweet and sour mix',
  'Tatlı sunumları için özel tasarım tabak':
      'Specially designed plate for sweet servings',
  'Tatlı çikolatanın sıcak kahveyle efsane uyumu.':
      'Legendary harmony of sweet chocolate with hot coffee.',
  'Tatlınıza veya içeceğinize ekstra çikolata/karamel sos':
      'Extra chocolate/caramel sauce to your dessert or drink',
  'Taze fırınlanmış badem kremalı kruvasan':
      'Freshly baked croissant with almond cream',
  'Taze muz dilimleri ilavesi': 'Fresh banana slice addition',
  'Taze yeşilliklerle dana jambonlu sandviç':
      'Beef ham sandwich with fresh greens',
  'Taze çilek dilimleri ilavesi': 'Fresh strawberry slice addition',
  'Tek kişilik taze meyveli hafif pasta': 'Light fresh fruit cake for one',
  'Tek kişilik özel tasarım kahve seti': 'Custom design coffee set for one',
  'Tek kullanımlık doğal süzme bal': 'Single-use natural strained honey',
  'Tek shot espresso': 'Single shot espresso',
  'Tost makinesinde ısıtılmış kaşarlı panini':
      'Panini with kashar cheese toasted in press',
  'Tropik meyveler ve yeşil elma boba ile canlı bir içim.':
      'A vibrant drink with tropical fruits and green apple boba.',
  'Tropikal lezzet': 'Tropical flavor',
  'Tropikal meyveli serinletici kokteyl': 'Refreshing tropical fruit cocktail',
  'Türk kahveli özel kokteyl': 'Special cocktail with Turkish coffee',
  'Uzak doğunun mistik bitkisel lezzeti':
      'Mystic herbal flavor of the Far East',
  '12 saat soğuk demleme, yumuşak içim ve ferah kahve aroması.':
      '12 hours cold brew, smooth taste, and refreshing coffee aroma.',
  'Vanilya ve kakaolu klasik mermer kek':
      'Classic marble cake with vanilla and cocoa',
  'Vanilya ve matcha füzyonu': 'Vanilla and matcha fusion',
  'Vanilya şurubu, sıcak süt, espresso ve nefis karamel.':
      'Vanilla syrup, hot milk, espresso and delicious caramel.',
  'Vanilyalı altın kokteyl': 'Vanilla gold cocktail',
  'Waffle aromalı taze sıkım': 'Freshly squeezed juice with waffle aroma',
  'Yanık kabuklu, akışkan içiyle İspanyol klasiği':
      'Spanish classic with burnt crust and creamy interior',
  'Karpuzun serinliği, çileğin tatlı aromasıyla birleşir.':
      'The coolness of watermelon meets the sweet aroma of strawberry.',
  'Yoğun bitter çikolata ve taze portakal aroması':
      'Intense dark chocolate and fresh orange flavor',
  'Yoğun fıstıklı dilimlenmiş dev cheesecake':
      'Giant sliced cheesecake with intense pistachio',
  'Yoğun kakao lezzeti': 'Intense cocoa flavor',
  'Yulaf ezmeli sağlıklı sandviç seçeneği': 'Healthy oatmeal sandwich option',
  'Yumuşak içimli sıcak süt ve dengeli espresso.':
      'Smooth hot milk and balanced espresso.',
  'Yumuşak sütlü espresso klasiği': 'Soft milk espresso classic',
  'Zencefil aromalı serinletici gazoz': 'Refreshing ginger flavored soda',
  'Zencefilli ejderha meyveli': 'Ginger dragon fruit',
  'Zeytinyağlı foccacia arası ezine': 'Ezine cheese in olive oil focaccia',
  'Çarkıfelek meyvesi ve çikolata buluşması':
      'Passion fruit and chocolate meeting',
  'Çift pişirme Türk kahvesi': 'Double brewed Turkish coffee',
  'Çift shot espresso': 'Double shot espresso',
  'Çikolata ve espresso buluşması': 'Chocolate and espresso meeting',
  'Çilek aromasıyla canlanan ferah ve serin limonata.':
      'Fresh and cool lemonade enlivened with strawberry aroma.',
  'Çilek, vanilya ve sihirli süslemeler':
      'Strawberry, vanilla and magic decorations',
  'Çilekli misket limonu': 'Strawberry lime',
  'Çocukların favorisi çikolatalı özel pasta':
      'Special chocolate cake - kids\' favorite',
  'Çıtır gofret parçalı rüya gibi çikolata':
      'Dreamlike chocolate with crispy wafer pieces',
  'Çıtır haşhaş ve taze limonlu kek dilimi':
      'Cake slice with crunchy poppy seeds and fresh lemon',
  'Özel baharatlar ve Madagaskar vanilyası harmanı':
      'Blend of special spices and Madagascar vanilla',
  'Özel cam şişede premium maden suyu':
      'Premium sparkling water in a special glass bottle',
  'Özel kubbe tasarım çikolatalı pasta': 'Special dome design chocolate cake',
  'Özel şekliyle orman meyveli çıtır tart':
      'Crispy tart with wild berries in a special shape',
  'Üstü dondurmalı sahlep': 'Sahlep topped with ice cream',
  'Üç çikolatalı yoğun brownie': 'Rich triple chocolate brownie',
  'İki kişilik şık Türk kahvesi fincan takımı':
      'Elegant Turkish coffee cup set for two',
  'İnce dokulu süt ile kadifemsi espresso':
      'Velvety espresso with microfoam milk',
  'İncecik süt köpüğü altında yoğun espresso deneyimi.':
      'Intense espresso experience under a thin layer of milk foam.',
  'İtalyan ekmeğinde ince dilim hindi füme':
      'Thinly sliced smoked turkey in Italian bread',
  'İtalyan klasiği; yoğun, sert ve uyanış garantili.':
      'Italian classic; intense, strong and guaranteed awakening.',
  'İtalyan pesto soslu ızgara tavuk':
      'Grilled chicken with Italian pesto sauce',
  'İçecekler için ekstra meyve püresi': 'Extra fruit puree for drinks',
  'İçeceğinize ekstra patlayan meyve incileri':
      'Extra popping fruit boba pearls for your drink',
  'İçeceğinize fındık aromalı bitkisel süt':
      'Hazelnut flavored plant-based milk for your drink',
  'İçeceğinize vegan badem sütü alternatifi':
      'Vegan almond milk alternative for your drink',
  'İçeceğinize vegan yulaf sütü alternatifi':
      'Vegan oat milk alternative for your drink',
  'İçeceğinizin veya tatlınızın yanına bir top dondurma':
      'A scoop of ice cream on the side of your drink or dessert',
  'İçeceğinizin üzerine taze krem şanti':
      'Fresh whipped cream on top of your drink',
  'İçi bol fıstıklı çıtır cheesecake':
      'Crispy cheesecake with plenty of pistachios inside',
  'İçi taze krema dolgulu çikolata topları':
      'Chocolate balls filled with fresh cream',
  'İçi ıslak, vişne taneli brownie rüyası':
      'Fudgy brownie dream with sour cherry pieces',

  // --- Missing Drink and Food Translations ---
  // Filtre & Sıcak Kahveler
  'Filtre Sütlü': 'Filter Coffee with Milk',
  'Klasik Filtre': 'Classic Filter Coffee',
  'Guatamala': 'Guatemala',
  'Damla Sakızlı Sahlep': 'Sahlep with Mastic Gum',
  'Dondurma Sahlep': 'Sahlep with Ice Cream',
  'Double Türk Kahvesi': 'Double Turkish Coffee',
  'Frambuazlı Sıcak Beyaz Çikolata': 'Raspberry Hot White Chocolate',
  'Tarçınlı Sahlep': 'Sahlep with Cinnamon',

  // Ice & Soğuk Kahveler
  'Ice Filtre Kahve': 'Iced Filter Coffee',
  'Ice Sütlü Filtre Kahve': 'Iced Filter Coffee with Milk',

  // Kokteyller & Bitki Çayları
  'Luuq Kuzu Kulağı Kokteyl': 'Luuq Sorrel Cocktail',
  'Ahududu Limon': 'Raspberry Lemon',
  'Gripsavar': 'Flu Fighter',
  'Limon Zencefil': 'Lemon Ginger',

  // Frozen & Bubble Tea
  'Frozen Ananas & Portakal & Limon': 'Frozen Pineapple & Orange & Lemon',
  'Frozen Karpuz & Çilek': 'Frozen Watermelon & Strawberry',
  'Frozen Orman Meyveleri': 'Frozen Forest Berries',
  'Frozen Yuzu & Şeftali': 'Frozen Yuzu & Peach',
  'Çilekli Limonata': 'Strawberry Lemonade',
  'Naneli Limonata': 'Mint Lemonade',

  // Milkshakeler & Meşrubatlar
  'Milkshake Beyaz Çikolata & Fındık': 'White Chocolate & Hazelnut Milkshake',
  'Milkshake Bitter & Portakal': 'Dark Chocolate & Orange Milkshake',
  'Milkshake Nutella': 'Nutella Milkshake',
  'Milkshake Tahin & Karamel & Çilek': 'Tahini, Caramel & Strawberry Milkshake',
  'Beyoğlu Klasik': 'Beyoglu Classic Soda',
  'Beyoğlu Reyhan': 'Beyoglu Basil Soda',
  'Beyoğlu Zencefil': 'Beyoglu Ginger Soda',
  'Damla Soda (200 ml)': 'Damla Mineral Water (200 ml)',
  'Damla Soda (330 ml)': 'Damla Mineral Water (330 ml)',
  'Damla Cam Su (330 ml)': 'Damla Still Water (330 ml)',
  'Uludağ Premium Soda': 'Uludag Premium Mineral Water',

  // Pastalar & Tatlılar
  'Allgo Dom Pasta': 'Allgo Dome Cake',
  'Ananas Badem Mono Pasta': 'Pineapple Almond Mono Cake',
  'Antep Dolgulu Cheesecake': 'Pistachio Filled Cheesecake',
  'Antep Fıstıklı Tart': 'Pistachio Tart',
  'Bademli Kruvasan': 'Almond Croissant',
  'Blondie Limon': 'Lemon Blondie',
  'Cheesecake Patlayan Şeker': 'Popping Candy Cheesecake',
  'Cheesecake San Sebastian': 'San Sebastian Cheesecake',
  'Çikolatalı Cookie Pie': 'Chocolate Cookie Pie',
  'Çikolatalı Tırtıl Pasta': 'Chocolate Caterpillar Cake',
  'Elmalı Tart': 'Apple Tart',
  'Fındıklı Kruvasan': 'Hazelnut Croissant',
  'Frambuaz & Antep Fıstıklı Kek': 'Raspberry & Pistachio Cake',
  'Frambuazlı Mono Pasta': 'Raspberry Mono Cake',
  'Kesme Fındıklı Pasta': 'Slices of Hazelnut Ice Cream Cake',
  'Lime Ekler': 'Lime Eclairs',
  'Limon & Frangipane Tart': 'Lemon & Frangipane Tart',
  'Limon & Haşhaşlı Baton Kek': 'Lemon & Poppy Seed Loaf Cake',
  'Lotus Mono Ekler': 'Lotus Mono Eclairs',
  'Luuq Çikolatalı Mousse Pasta': 'LUUQ Chocolate Mousse Cake',
  'Mermer Baton Kek': 'Classic Marble Loaf Cake',
  'Orman Meyveli Cup': 'Wild Berry Cup Dessert',
  'Orman Meyveli Elips Tart': 'Wild Berry Ellipse Tart',
  'Passion & Çikolatalı Tart': 'Passion Fruit & Chocolate Tart',
  'Smores Cup': 'S\'mores Cup Dessert',
  'Trio Chocolate Browni': 'Trio Chocolate Brownie',
  'Üçgen Dilim Fıstıklı Cheesecake': 'Triangle Slice Pistachio Cheesecake',
  'Vişneli Tart': 'Cherry Tart',
  'Vişneli Brownie': 'Cherry Brownie',
  'White Cascada Dom Pasta': 'White Cascada Dome Cake',
  'Yanık Cheesecake': 'Burnt Cheesecake',
  'Çilek Limon Mono Pasta': 'Strawberry Lemon Mono Cake',
  'Limonlu Pasta': 'Lemon Cake',
  'Özel krema dolgulu enfes brownie rüyası':
      'Delicious brownie dream with special cream filling',
  'Çilek ve limon ferahlığıyla mono pasta':
      'Mono cake with strawberry and lemon freshness',
  'Limon soslu ve kremalı nefis pasta dilimi':
      'Delicious cake slice with lemon sauce and cream',

  // Sandviçler
  'Dana Jambon': 'Beef Ham',
  'Haşhaşlı Cabata Sandviç': 'Poppy Seed Ciabatta Sandwich',
  'Ezine Peynirli Tahıllı Cabata Sandviç':
      'Ezine Cheese Whole Grain Ciabatta Sandwich',
  'Haşhaşlı 4 Peynirli Bagel Sandviç': 'Poppy Seed 4-Cheese Bagel Sandwich',
  'Haşhaşlı Cabata Hindi Füme Tahıllı':
      'Poppy Seed Whole Grain Smoked Turkey Ciabatta',
  'Cabata Sandviç': 'Ciabatta Sandwich',
  'Pesto Soslu Tavuklu Sandviç': 'Pesto Chicken Sandwich',
  'Tahıllı Üçgen Panini': 'Whole Grain Triangle Panini',
  'Yedi Foccacia Ezine Peynirli Sandviç':
      'Olive Oil Focaccia Ezine Cheese Sandwich',
  'Yedi Foccacia Hindi Sandviç': 'Olive Oil Focaccia Turkey Sandwich',
  'Yedi Roast Beef Sandviç': 'Roast Beef Sandwich',
  'Yulaflı Cabata': 'Oatmeal Ciabatta',

  // Termos & Seramikler
  'Seramik Demlik': 'Ceramic Teapot',
  'Seramik Double Türk Kahvesi Seti': 'Ceramic Double Turkish Coffee Cup Set',
  'Seramik Kupa - Altlık': 'Handmade Ceramic Mug & Saucer',
  'Seramik Pasta Tabağı': 'Ceramic Dessert Plate',
  'Seramik Türk Kahvesi Seti': 'Ceramic Turkish Coffee Cup Set',
  'Trm04s Rose 400 ml Termos': 'Trm04s Rose 400 ml Thermos',
  'Trm094 Beyaz Ofset 350 ml Çelik Termos':
      'Trm094 White Offset 350 ml Steel Thermos',
  'Trm094 K.rengi Ofset 350 ml Çelik Termos':
      'Trm094 Brown Offset 350 ml Steel Thermos',
  'Trm119 Siyah 500 ml Çelik Mug Termos':
      'Trm119 Black 500 ml Steel Travel Mug',
  'Trm159 Haki 350 ml Çelik Termos': 'Trm159 Khaki 350 ml Steel Thermos',
  'Trm159 Krem 350 ml Çelik Termos': 'Trm159 Cream 350 ml Steel Thermos',
  'Trm175 Siyah 500 ml Çelik Termos': 'Trm175 Black 500 ml Steel Thermos',
  'Trm173 Yeşil 350 ml Çelik Termos': 'Trm173 Green 350 ml Steel Thermos',
  'Trm185-B 380 ml Beyaz Termos': 'Trm185-B 380 ml White Thermos',
  'Trm185-G 380 ml Gri Termos': 'Trm185-G 380 ml Gray Thermos',

  // Ekstralar
  'Bademli Süt': 'Almond Milk',
  'Bubble': 'Boba Pearls',
  'Balparmak (7 gr)': 'Balparmak Honey (7g)',
  'Calebaut': 'Callebaut Chocolate',
  'Dondurma': 'Ice Cream',
  'Ekstra Çilek (Meyve)': 'Extra Strawberry (Fruit)',
  'Ekstra Muz (Meyve)': 'Extra Banana (Fruit)',
  'Laktozsuz Süt': 'Lactose-Free Milk',
  'Fındık Süt': 'Hazelnut Milk',
  'Krema': 'Cream',
  'Püre': 'Puree',
  'Shot': 'Espresso Shot',
  'Sos': 'Sauce',
  'Şurup': 'Syrup',
  'Yulaf Süt': 'Oat Milk',
};

String trMenu(String text) {
  if (appLanguageNotifier.value == AppLanguage.tr) return text;
  return _menuDict[text] ?? text;
}

/// Remote catalogs default missing English text to the Turkish value, so an
/// English field that is blank or identical to Turkish counts as untranslated
/// and falls through to the bundled dictionary.
String? _translatedOrNull(String? english, String turkish) {
  if (english == null) return null;
  final trimmed = english.trim();
  return trimmed.isEmpty || trimmed == turkish.trim() ? null : english;
}

String _menuItemName(_MenuItem item) => menuTextForLanguage(
  turkish: item.name,
  english: _translatedOrNull(item.nameEn, item.name) ?? _menuDict[item.name],
  useEnglish: appLanguageNotifier.value == AppLanguage.en,
);
String _menuItemDescription(_MenuItem item) => menuTextForLanguage(
  turkish: item.desc,
  english: _translatedOrNull(item.descEn, item.desc) ?? _menuDict[item.desc],
  useEnglish: appLanguageNotifier.value == AppLanguage.en,
);
String _menuItemTag(_MenuItem item, String tag) {
  final index = item.tags.indexOf(tag);
  final english = index >= 0 && index < item.tagsEn.length
      ? item.tagsEn[index]
      : null;
  return menuTextForLanguage(
    turkish: tag,
    english: _translatedOrNull(english, tag) ?? _menuDict[tag],
    useEnglish: appLanguageNotifier.value == AppLanguage.en,
  );
}

String _menuCategoryName(String categoryKey) => menuTextForLanguage(
  turkish: categoryKey,
  english:
      _translatedOrNull(_activeMenuCategoryNamesEn[categoryKey], categoryKey) ??
      _menuDict[categoryKey],
  useEnglish: appLanguageNotifier.value == AppLanguage.en,
);
String _menuCategoryDescription(String categoryKey) =>
    appLanguageNotifier.value == AppLanguage.en
    ? _activeMenuCategoryDescriptionsEn[categoryKey] ??
          _activeMenuCategoryDescriptions[categoryKey] ??
          ''
    : _activeMenuCategoryDescriptions[categoryKey] ?? '';
