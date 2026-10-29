import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------- Supabase settings (Project Settings > API in the dashboard) ----------
const kSupabaseUrl = 'https://ilotwfcyclenxsliwbsn.supabase.co';
const kSupabaseKey =
    'sb_publishable_ge0tMoVWPGUavKyjTjjRTg_nybr5o0X'; // anon / publishable key only. NEVER the service_role key.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kSupabaseUrl, publishableKey: kSupabaseKey);
  runApp(const CiMakeupApp());
}

SupabaseClient get db => Supabase.instance.client;

// True while an order is being sent to Supabase (disables the button)
final ValueNotifier<bool> placingOrder = ValueNotifier<bool>(false);

// ---------- Theme / constants (colors taken from the mockup) ----------
const kBg = Color(0xFFFFF1E8); // peach background
const kPink = Color(0xFFFF7FAE); // "Make Up & Brush Brand" script text
const kGreen = Color(0xFF00B96B); // product title
const kYellow = Color(0xFFF7BE2E); // Add to cart button
const kStar = Color(0xFFFFB400);

// Current bottom-tab (lets the side menu switch tabs)
final ValueNotifier<int> tabIndex = ValueNotifier<int>(0);

// ---------- Cart (state + helpers) ----------
const kProductName = 'One Set Make Up & Tools';
const kProductImage = 'assets/images/hero_set.jpg';
const kProductPrice = 4999;
const kShippingFee = 30;

class CartItem {
  final String name, image;
  final int price, qty;
  const CartItem({
    required this.name,
    required this.image,
    required this.price,
    required this.qty,
  });
  CartItem copyWith({int? qty}) =>
      CartItem(name: name, image: image, price: price, qty: qty ?? this.qty);
}

final ValueNotifier<List<CartItem>> cart = ValueNotifier<List<CartItem>>([]);

/// Add a product to the cart. replace=true sets the quantity instead of adding.
void addToCart(
  int qty, {
  bool replace = false,
  String name = kProductName,
  String image = kProductImage,
  int price = kProductPrice,
}) {
  final list = List<CartItem>.from(cart.value);
  final i = list.indexWhere((e) => e.name == name);
  if (i >= 0) {
    list[i] = list[i].copyWith(qty: replace ? qty : list[i].qty + qty);
  } else {
    list.add(CartItem(name: name, image: image, price: price, qty: qty));
  }
  cart.value = list;
}

/// (Optional) Add 1 of a product and jump straight to the Order Summary.
void buyNow(BuildContext context, String name, String image, int price) {
  addToCart(1, name: name, image: image, price: price);
  Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage()));
}

void setCartQty(String name, int qty) {
  final list = List<CartItem>.from(cart.value);
  final i = list.indexWhere((e) => e.name == name);
  if (i < 0) return;
  if (qty <= 0) {
    list.removeAt(i);
  } else {
    list[i] = list[i].copyWith(qty: qty);
  }
  cart.value = list;
}

int cartCount(List<CartItem> items) => items.fold(0, (a, e) => a + e.qty);
int cartSubtotal(List<CartItem> items) =>
    items.fold(0, (a, e) => a + e.price * e.qty);

String peso(int v) =>
    '\u20B1${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

// ---------- Wishlist (state + helpers) ----------
// Saved products. Products are plain Category objects (name, image, price).
final ValueNotifier<List<Category>> wishlist = ValueNotifier<List<Category>>(
  [],
);

bool isWished(String name) => wishlist.value.any((e) => e.name == name);

/// Heart tapped: add if not saved yet, otherwise remove. Returns true if added.
bool toggleWish(Category p) {
  final list = List<Category>.from(wishlist.value);
  final i = list.indexWhere((e) => e.name == p.name);
  if (i >= 0) {
    list.removeAt(i);
    wishlist.value = list;
    return false;
  }
  list.add(p);
  wishlist.value = list;
  return true;
}

// ---------- Account (state) ----------
class Account {
  final String name, phone, email;
  const Account({required this.name, required this.phone, required this.email});
}

/// Pre-registered account (edit the details on the Account tab, or here)
final ValueNotifier<Account?> account = ValueNotifier<Account?>(
  const Account(
    name: 'Jeancel Ibay',
    phone: '09123456789', // replace with her real mobile number
    email: 'jeancel.ibay@gmail.com', // replace with her real email address
  ),
);

class CiMakeupApp extends StatelessWidget {
  const CiMakeupApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'C.I Make Up Brand',
        theme: ThemeData(
          scaffoldBackgroundColor: kBg,
          fontFamily: 'Calibri', // falls back to default if not installed
          colorScheme: ColorScheme.fromSeed(seedColor: kPink),
        ),
        home: const RootShell(),
      );
}

// ---------- Data (images = exact pictures from the mockup) ----------
class Category {
  final String name, image;
  final int price; // edit these prices to your real prices
  final String? category;
  const Category(this.name, this.image, this.price, {this.category});
}

Widget _productImage(String path, {required BoxFit fit}) {
  final uri = Uri.tryParse(path);
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    return Image.asset(path, fit: fit);
  }
  return Image.network(
    path,
    fit: fit,
    errorBuilder: (_, __, ___) => const Center(
      child: Icon(Icons.broken_image_outlined, size: 36),
    ),
  );
}

const toolItems = <Category>[
  Category('Puff', 'assets/images/puff.jpg', 150),
  Category('Settings Spray', 'assets/images/setting_spray.jpg', 350),
  Category('Brush', 'assets/images/brush.jpg', 600),
];

Future<List<Category>>? _productCatalogFuture;

Future<List<Category>> loadProductCatalog({bool refresh = false}) {
  if (refresh || _productCatalogFuture == null) {
    _productCatalogFuture = _fetchProductCatalog();
  }
  return _productCatalogFuture!;
}

Future<List<Category>> _fetchProductCatalog() async {
  final rows = await db
      .from('products')
      .select('name, category, price, image_url')
      .order('id');
  return rows.map((row) {
    final name = row['name'];
    final category = row['category'];
    final price = row['price'];
    final image = row['image_url'];
    if (name is! String ||
        category is! String ||
        price is! num ||
        image is! String) {
      throw const FormatException(
        'The products table must have name, category, numeric price, and image_url fields.',
      );
    }
    return Category(
      name,
      image,
      price.toInt(),
      category: category,
    );
  }).toList();
}

// Small yellow "add to cart" icon on each product picture.
// Adds the item and stays on the page; the customer reviews it later
// in the Order Summary (cart icon at the top) and places the order there.
class AddCartIcon extends StatelessWidget {
  final String name, image;
  final int price;
  const AddCartIcon({
    super.key,
    required this.name,
    required this.image,
    required this.price,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: kYellow,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          addToCart(1, name: name, image: image, price: price);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 3),
                content: Text('$name added to cart'),
                action: SnackBarAction(
                  label: 'VIEW CART',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CartPage()),
                  ),
                ),
              ),
            );
        },
        child: const Padding(
          padding: EdgeInsets.all(7),
          child: Icon(Icons.add_shopping_cart, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

// ---------- Shell with bottom navigation ----------
class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tabIndex,
      builder: (context, i, _) {
        final pages = [
          const HomePage(),
          const CategoryPage(),
          const WishlistPage(),
          const AccountPage(),
        ];
        return Scaffold(
          drawer: const AppDrawer(),
          body: SafeArea(child: pages[i]),
          bottomNavigationBar: BottomNav(
            index: i,
            onTap: (v) => tabIndex.value = v,
          ),
        );
      },
    );
  }
}

class BottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const BottomNav({super.key, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Filled home, grid, outlined heart, outlined person (as in mockup)
    final items = [
      (Icons.home_filled, 'Home'),
      (Icons.grid_view_outlined, 'Category'),
      (Icons.favorite_border, 'Wishlist'),
      (Icons.person_outline, 'Account'),
    ];
    return Container(
      color: kBg,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (int k = 0; k < items.length; k++)
              InkWell(
                onTap: () => onTap(k),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(items[k].$1, size: 40, color: Colors.black),
                    Text(
                      items[k].$2,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withOpacity(k == index ? 1 : .85),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------- Shared pieces ----------
class CartButton extends StatelessWidget {
  const CartButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CartItem>>(
      valueListenable: cart,
      builder: (context, items, _) {
        final n = cartCount(items);
        return InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CartPage()),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.add_shopping_cart_outlined,
                size: 44,
                color: Colors.black,
              ),
              if (n > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$n',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class SubHeader extends StatelessWidget {
  final bool showBack, showCart;
  final String title;
  const SubHeader({
    super.key,
    this.showBack = true,
    this.showCart = true,
    this.title = 'All Shades for Light & Dark Skin',
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 44,
                icon: const Icon(Icons.menu, color: Colors.black), // hamburger
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              showCart ? const CartButton() : const SizedBox(width: 44),
            ],
          ),
          if (showBack)
            InkWell(
              onTap: () => Navigator.maybePop(context),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.keyboard_return, size: 40), // "Back" arrow
                  SizedBox(width: 8),
                  Text(
                    'Back',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------- Side menu (opens from the hamburger icon) ----------
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  void _goTab(BuildContext context, int tab) {
    Navigator.pop(context); // close the drawer
    Navigator.popUntil(context, (r) => r.isFirst);
    tabIndex.value = tab;
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: kBg,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.black),
            child: Center(
              child: ClipOval(
                child: Image.asset('assets/images/logo.png', height: 110),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home_filled),
            title: const Text('Home'),
            onTap: () => _goTab(context, 0),
          ),
          ListTile(
            leading: const Icon(Icons.grid_view_outlined),
            title: const Text('Category'),
            onTap: () => _goTab(context, 1),
          ),
          ListTile(
            leading: const Icon(Icons.brush_outlined),
            title: const Text('Tools: Puff · Spray · Brush'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ToolsPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('Wishlist'),
            onTap: () => _goTab(context, 2),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Account'),
            onTap: () => _goTab(context, 3),
          ),
        ],
      ),
    );
  }
}

// ---------- HOME ----------
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ctrl = TextEditingController();
  final _page = PageController();
  int _p = 0;
  String _q = ''; // what the customer typed in the search bar
  // Banner pictures: first one is the mockup photo; add more as assets.
  final banners = const [
    'assets/images/banner_1.jpg',
    'assets/images/hero_set.jpg',
  ];

  // lower-case and drop spaces/symbols so "eyeshadow" finds "Eye Shadow"
  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  List<Category> _results(List<Category> products) {
    final q = _norm(_q);
    if (q.isEmpty) return [];
    final all = <Category>[
      const Category(kProductName, kProductImage, kProductPrice),
      ...products,
      ...toolItems,
    ];
    return all.where((c) => _norm(c.name).contains(q)).toList();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searching = _norm(_q).isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Row(
          children: [
            ClipOval(
              child: Image.asset(
                'assets/images/logo.png',
                width: 95,
                height: 95,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  const Text(
                    'Make Up & Brush Brand',
                    style: TextStyle(
                      fontFamily: 'cursive',
                      fontStyle: FontStyle.italic,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: kPink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, size: 30),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            textInputAction: TextInputAction.search,
                            onChanged: (v) => setState(() => _q = v),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              hintText: 'Search products',
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            _ctrl.clear();
                            setState(() => _q = '');
                          },
                          child: const Icon(Icons.close, size: 28),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Align(alignment: Alignment.topCenter, child: CartButton()),
          ],
        ),
        const SizedBox(height: 20),
        if (!searching) ...[
          SizedBox(
            height: 260,
            child: Row(
              children: [
                IconButton(
                  iconSize: 44,
                  onPressed: () => _page.previousPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  ),
                  icon: const Icon(Icons.chevron_left, weight: 100),
                ),
                Expanded(
                  child: PageView(
                    controller: _page,
                    onPageChanged: (v) => setState(() => _p = v),
                    children: [
                      for (final b in banners)
                        Image.asset(b, fit: BoxFit.cover),
                    ],
                  ),
                ),
                IconButton(
                  iconSize: 44,
                  onPressed: () => _page.nextPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < 4; i++)
                Container(
                  width: 34,
                  height: 28,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i == _p
                        ? const Color(0xFF2B2E2E)
                        : const Color(0xFFCDD1D0),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
            ],
          ),
        ] else
          FutureBuilder<List<Category>>(
            future: loadProductCatalog(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text('Could not load products: ${snapshot.error}'),
                      TextButton(
                        onPressed: () => setState(
                          () => loadProductCatalog(refresh: true),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              final results = _results(snapshot.data!);
              if (results.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    children: [
                      const Icon(Icons.search_off, size: 70),
                      const SizedBox(height: 10),
                      Text(
                        'No products found for "${_q.trim()}"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Try: lipstick, blush, foundation, brush...',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      '${results.length} result(s) for "${_q.trim()}"',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: .78,
                    children: [
                      for (final c in results)
                        _Tile(
                          c,
                          onTap: c.name == kProductName
                              ? () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ProductDetailPage(),
                                    ),
                                  )
                              : () {},
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

// ---------- CATEGORY (lipstick, blush ... + tools) ----------
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  Future<List<Category>> _products = loadProductCatalog();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SubHeader(showBack: false),
        Expanded(
          child: FutureBuilder<List<Category>>(
            future: _products,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Could not load products: ${snapshot.error}'),
                        TextButton(
                          onPressed: () => setState(
                            () => _products = loadProductCatalog(refresh: true),
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final products = snapshot.data!;
              if (products.isEmpty) {
                return const Center(child: Text('No products are available.'));
              }
              return GridView.count(
                crossAxisCount: 3,
                padding: const EdgeInsets.all(10),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: .78,
                children: [
                  for (final product in products)
                    _Tile(product, onTap: () {}),
                ],
              );
            },
          ),
        ),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ToolsPage()),
          ),
          child: const Text(
            'Tools: Puff · Settings Spray · Brush  →',
            style: TextStyle(color: Colors.black),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final Category c;
  final VoidCallback onTap;
  const _Tile(this.c, {required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _productImage(c.image, fit: BoxFit.cover),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: AddCartIcon(
                      name: c.name,
                      image: c.image,
                      price: c.price,
                    ),
                  ),
                  Positioned(right: 4, top: 4, child: WishHeart(product: c)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              c.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
}

// ---------- TOOLS page (second page, from the mockup) ----------
class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: kBg,
      body: SafeArea(
        // Whole page scrolls (header included), so it can never overflow
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SubHeader(), // menu, title, cart, Back
              // Set photo: tap to open the product page
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProductDetailPage()),
                ),
                child: SizedBox(
                  width: w * 0.36,
                  child: AspectRatio(
                    aspectRatio: 356 / 330,
                    child: Image.asset(
                      'assets/images/hero_set.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Expanded(
                      child: ToolTile(
                        'Puff',
                        'assets/images/puff.jpg',
                        150,
                        contain: true,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: ToolTile(
                        'Settings Spray',
                        'assets/images/setting_spray.jpg',
                        350,
                        contain: true,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: ToolTile('Brush', 'assets/images/brush.jpg', 600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNav(
        index: 1,
        onTap: (k) {
          tabIndex.value = k;
          Navigator.popUntil(context, (r) => r.isFirst);
        },
      ),
    );
  }
}

class ToolTile extends StatelessWidget {
  final String label, image;
  final int price;
  final bool contain;
  const ToolTile(
    this.label,
    this.image,
    this.price, {
    super.key,
    this.contain = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: Colors.white,
                child: Image.asset(
                  image,
                  fit: contain ? BoxFit.contain : BoxFit.cover,
                ),
              ),
              Positioned(
                right: 4,
                bottom: 4,
                child: AddCartIcon(name: label, image: image, price: price),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: WishHeart(product: Category(label, image, price)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

// ---------- PRODUCT DETAIL ----------
class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({super.key});
  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  int qty = 1;
  static const price = 4999;
  static const shipping = 30;

  @override
  Widget build(BuildContext context) {
    final total = price * qty + shipping;
    return Scaffold(
      drawer: const AppDrawer(),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SubHeader(),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset(
                      'assets/images/hero_set.jpg',
                      width: 140,
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Expanded(
                                child: Text(
                                  'One Set Make Up & Tools',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: kGreen,
                                  ),
                                ),
                              ),
                              WishHeart(
                                product: Category(
                                  kProductName,
                                  kProductImage,
                                  kProductPrice,
                                ),
                              ),
                            ],
                          ),
                          const Text(
                            '₱ 4,999',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Row(
                            children: List.generate(
                              5,
                              (_) => const Icon(
                                Icons.star,
                                color: kStar,
                                size: 28,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Whole Set of make up and brushes long- lasting and soft bristles . All skin type',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              IconButton(
                                onPressed: () =>
                                    setState(() => qty = qty > 1 ? qty - 1 : 1),
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 34,
                                ),
                              ),
                              Container(
                                width: 38,
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(),
                                ),
                                child: Text('$qty'),
                              ),
                              IconButton(
                                onPressed: () => setState(() => qty++),
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  size: 34,
                                ),
                              ),
                            ],
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                addToCart(qty);
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    SnackBar(
                                      content: Text('Added $qty to cart'),
                                      action: SnackBarAction(
                                        label: 'VIEW CART',
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const CartPage(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kYellow,
                                foregroundColor: Colors.white,
                                shape: const StadiumBorder(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                              icon: const CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.white,
                                child: Icon(
                                  Icons.shopping_cart,
                                  color: kYellow,
                                  size: 20,
                                ),
                              ),
                              label: const Text(
                                'ADD TO CART',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payment Details',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Total: ₱$total',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'Shipping Fee:   30',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          addToCart(qty, replace: true);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CartPage()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          'PLACE ORDER',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNav(
        index: 1,
        onTap: (k) {
          tabIndex.value = k;
          Navigator.popUntil(context, (r) => r.isFirst);
        },
      ),
    );
  }
}

// ---------- ORDER SUMMARY (cart) ----------
class CartPage extends StatelessWidget {
  const CartPage({super.key});

  /// Saves the order to Supabase (table: orders), then shows the confirmation.
  Future<void> _placeOrder(BuildContext context, List<CartItem> items) async {
    final messenger = ScaffoldMessenger.of(context);
    final acc = account.value;
    if (acc == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please register your account first.')),
      );
      tabIndex.value = 3;
      Navigator.popUntil(context, (r) => r.isFirst);
      return;
    }

    final subtotal = cartSubtotal(items);
    final total = subtotal + kShippingFee;
    final orderNo =
        'CI-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';

    placingOrder.value = true;
    String payUrl;
    try {
      await db.from('orders').insert({
        'order_no': orderNo,
        'customer_name': acc.name,
        'customer_phone': acc.phone,
        'customer_email': acc.email,
        'items': [
          for (final i in items)
            {'name': i.name, 'price': i.price, 'qty': i.qty},
        ],
        'subtotal': subtotal,
        'shipping': kShippingFee,
        'total': total,
      });

      // Ask the server to create the Xendit payment page for this order.
      final res = await db.functions.invoke(
        'cimakeup-api',
        body: {'order_no': orderNo},
      );
      payUrl = (res.data as Map)['invoice_url'] as String;
    } catch (e) {
      placingOrder.value = false;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not place order: $e')),
      );
      return; // Cart is kept so the customer can try again.
    }

    placingOrder.value = false;
    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kBg,
        title: const Text('Order placed!'),
        content: Text(
          'Order #$orderNo\n'
          'Name: ${acc.name}\nContact: ${acc.phone}\nEmail: ${acc.email}\n'
          'Total: ${peso(total)}\n\n'
          'Tap PAY NOW to pay with GCash, credit/debit card and more.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final launched = await launchUrl(
                Uri.parse(payUrl),
                mode: LaunchMode.externalApplication,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (!launched && context.mounted) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Could not open the payment page.'),
                  ),
                );
              }
            },
            child: const Text('PAY NOW'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    cart.value = [];
    tabIndex.value = 0;
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: kBg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SubHeader(title: 'Order Summary', showCart: false),
              ValueListenableBuilder<List<CartItem>>(
                valueListenable: cart,
                builder: (context, items, _) {
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          const Icon(Icons.shopping_cart_outlined, size: 90),
                          const SizedBox(height: 12),
                          const Text(
                            'Your cart is empty',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () =>
                                Navigator.popUntil(context, (r) => r.isFirst),
                            child: const Text('Continue shopping'),
                          ),
                        ],
                      ),
                    );
                  }
                  final subtotal = cartSubtotal(items);
                  final total = subtotal + kShippingFee;
                  return Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        for (final it in items) _CartRow(it),
                        const Divider(thickness: 1.5, height: 30),
                        _SumRow(
                          'Subtotal (${cartCount(items)} item/s)',
                          peso(subtotal),
                        ),
                        _SumRow('Shipping Fee', peso(kShippingFee)),
                        const Divider(height: 24),
                        _SumRow('Total', peso(total), bold: true),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          child: ValueListenableBuilder<bool>(
                            valueListenable: placingOrder,
                            builder: (context, busy, _) => ElevatedButton(
                              onPressed: busy
                                  ? null
                                  : () => _placeOrder(context, items),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: const StadiumBorder(),
                              ),
                              child: busy
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'PLACE ORDER',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNav(
        index: 1,
        onTap: (k) {
          tabIndex.value = k;
          Navigator.popUntil(context, (r) => r.isFirst);
        },
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  final CartItem it;
  const _CartRow(this.it);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          height: 100,
          child: _productImage(it.image, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                it.name,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: kGreen,
                ),
              ),
              Text(
                peso(it.price),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setCartQty(it.name, it.qty - 1),
                    icon: const Icon(Icons.remove_circle_outline, size: 32),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(),
                    ),
                    child: Text('${it.qty}'),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setCartQty(it.name, it.qty + 1),
                    icon: const Icon(Icons.add_circle_outline, size: 32),
                  ),
                  const Spacer(),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setCartQty(it.name, 0),
                    icon: const Icon(Icons.delete_outline, size: 30),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SumRow extends StatelessWidget {
  final String label, value;
  final bool bold;
  const _SumRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final st = TextStyle(
      fontSize: bold ? 24 : 19,
      fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: st)),
          Text(value, style: st),
        ],
      ),
    );
  }
}

// ---------- WISHLIST ----------
// Heart button shown on every product picture. Tap = save / unsave.
class WishHeart extends StatelessWidget {
  final Category product;
  const WishHeart({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Category>>(
      valueListenable: wishlist,
      builder: (context, list, _) {
        final on = list.any((e) => e.name == product.name);
        return Material(
          color: Colors.white.withOpacity(.9),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              final added = toggleWish(product);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 2),
                    content: Text(
                      added
                          ? '${product.name} saved to wishlist'
                          : '${product.name} removed from wishlist',
                    ),
                    action: added
                        ? SnackBarAction(
                            label: 'VIEW',
                            onPressed: () {
                              Navigator.popUntil(context, (r) => r.isFirst);
                              tabIndex.value = 2;
                            },
                          )
                        : null,
                  ),
                );
            },
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                on ? Icons.favorite : Icons.favorite_border,
                size: 22,
                color: on ? Colors.red : Colors.black,
              ),
            ),
          ),
        );
      },
    );
  }
}

class WishlistPage extends StatelessWidget {
  const WishlistPage({super.key});

  void _toCart(BuildContext context, List<Category> items) {
    for (final p in items) {
      addToCart(1, name: p.name, image: p.image, price: p.price);
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            items.length == 1
                ? '${items.first.name} added to cart'
                : '${items.length} items added to cart',
          ),
          action: SnackBarAction(
            label: 'VIEW CART',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CartPage()),
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SubHeader(showBack: false, title: 'My Wishlist'),
        Expanded(
          child: ValueListenableBuilder<List<Category>>(
            valueListenable: wishlist,
            builder: (context, items, _) {
              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite_border, size: 90),
                        const SizedBox(height: 12),
                        const Text(
                          'Your wishlist is empty',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Tap the heart on any product to save it here.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => tabIndex.value = 1,
                          child: const Text('Browse products'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          '${items.length} saved item(s)',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => wishlist.value = [],
                              child: const Text(
                                'Clear all',
                                style: TextStyle(color: Colors.black),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _toCart(context, items),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kYellow,
                                foregroundColor: Colors.white,
                                shape: const StadiumBorder(),
                              ),
                              icon: const Icon(
                                Icons.add_shopping_cart,
                                size: 20,
                              ),
                              label: const Text('Add all to cart'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 18),
                      itemBuilder: (context, i) {
                        final p = items[i];
                        return Row(
                          children: [
                            Container(
                              color: Colors.white,
                              child: SizedBox(
                                width: 80,
                                height: 80,
                                child: _productImage(
                                  p.image,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: kGreen,
                                    ),
                                  ),
                                  Text(
                                    peso(p.price),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Add to cart',
                              onPressed: () => _toCart(context, [p]),
                              style: IconButton.styleFrom(
                                backgroundColor: kYellow,
                              ),
                              icon: const Icon(
                                Icons.add_shopping_cart,
                                color: Colors.white,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              onPressed: () => toggleWish(p),
                              icon: const Icon(Icons.delete_outline, size: 28),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------- ACCOUNT (register: name, mobile number, email) ----------
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  static const _defaultName = 'Jeancel Ibay';
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    final a = account.value;
    _name = TextEditingController(text: a?.name ?? _defaultName);
    _phone = TextEditingController(text: a?.phone ?? '');
    _email = TextEditingController(text: a?.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final isNew = account.value == null;
    account.value = Account(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
    );
    setState(() => _editing = false);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(isNew ? 'Account registered!' : 'Account updated'),
        ),
      );
  }

  void _remove() {
    account.value = null;
    _name.text = _defaultName;
    _phone.clear();
    _email.clear();
    setState(() => _editing = false);
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon,
    String? Function(String?) validator, {
    TextInputType? type,
    List<TextInputFormatter>? formatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        keyboardType: type,
        inputFormatters: formatters,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _formView(bool isNew) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isNew ? 'Register your account' : 'Edit your details',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text('Your details are used for your orders.'),
          const SizedBox(height: 18),
          _field(_name, 'Full name', Icons.person_outline, (v) {
            if (v == null || v.trim().length < 2) return 'Enter your full name';
            return null;
          }),
          _field(
            _phone,
            'Mobile number',
            Icons.phone_outlined,
            (v) {
              final t = (v ?? '').trim();
              if (!RegExp(r'^(09|\+639)\d{9}$').hasMatch(t)) {
                return 'Enter a valid number, e.g. 09123456789';
              }
              return null;
            },
            type: TextInputType.phone,
            formatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
              LengthLimitingTextInputFormatter(13),
            ],
          ),
          _field(_email, 'Email address', Icons.email_outlined, (v) {
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                .hasMatch((v ?? '').trim())) {
              return 'Enter a valid email address';
            }
            return null;
          }, type: TextInputType.emailAddress),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: kGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const StadiumBorder(),
              ),
              child: Text(
                isNew ? 'REGISTER' : 'SAVE CHANGES',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          if (!isNew)
            Center(
              child: TextButton(
                onPressed: () {
                  final a = account.value!;
                  _name.text = a.name;
                  _phone.text = a.phone;
                  _email.text = a.email;
                  setState(() => _editing = false);
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _profileView(Account a) {
    Widget row(IconData icon, String label, String value) => ListTile(
          leading: Icon(icon, color: Colors.black),
          title: Text(label, style: const TextStyle(fontSize: 13)),
          subtitle: Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        );
    return Column(
      children: [
        CircleAvatar(
          radius: 46,
          backgroundColor: kPink,
          child: Text(
            _initials(a.name),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          a.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Chip(
          avatar: Icon(Icons.check_circle, color: kGreen, size: 20),
          label: Text('Registered account'),
          backgroundColor: Colors.white,
        ),
        const SizedBox(height: 14),
        Card(
          color: Colors.white,
          child: Column(
            children: [
              row(Icons.person_outline, 'Name', a.name),
              const Divider(height: 1),
              row(Icons.phone_outlined, 'Mobile number', a.phone),
              const Divider(height: 1),
              row(Icons.email_outlined, 'Email', a.email),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _editing = true),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit details'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: kBg,
              title: const Text('Remove account?'),
              content: const Text(
                'Your saved name, number and email will be removed.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _remove();
                  },
                  child: const Text(
                    'Remove',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
          icon: const Icon(Icons.logout, color: Colors.red),
          label: const Text(
            'Remove account',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SubHeader(showBack: false, title: 'My Account'),
        Expanded(
          child: ValueListenableBuilder<Account?>(
            valueListenable: account,
            builder: (context, acc, _) => SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: (acc == null || _editing)
                  ? _formView(acc == null)
                  : _profileView(acc),
            ),
          ),
        ),
      ],
    );
  }
}
