import Image from "next/image";
import Link from "next/link";

const features = [
  {
    number: "01",
    title: "Take orders with ease",
    description:
      "Keep checkout moving with a clear point of sale built for everyday service.",
    icon: "◫",
  },
  {
    number: "02",
    title: "Know your numbers",
    description:
      "Review sales, transactions, and performance from one straightforward dashboard.",
    icon: "↗",
  },
  {
    number: "03",
    title: "Stay on top of stock",
    description:
      "Track inventory, record restocks, and connect ingredients to your recipes.",
    icon: "▤",
  },
  {
    number: "04",
    title: "Give your team the right access",
    description:
      "Manage staff accounts and choose which POS features each person can use.",
    icon: "◎",
  },
];

const stories = [
  {
    image:
      "https://images.unsplash.com/photo-1586864030223-a918b07d357d?auto=format&fit=crop&w=1400&q=85",
    alt: "Tablet point-of-sale terminal on a bakery counter",
    title: "Checkout that keeps the line moving",
  },
  {
    image:
      "https://images.unsplash.com/photo-1607539068168-21a93fbedad8?auto=format&fit=crop&w=1200&q=85",
    alt: "Barista preparing coffee at an espresso machine",
    title: "More time for the work you love",
  },
  {
    image:
      "https://images.unsplash.com/photo-1723214488726-7f59d85082ab?auto=format&fit=crop&w=1200&q=85",
    alt: "Coffee beans organized in labeled jars on café shelves",
    title: "Keep ingredients and stock in view",
  },
];

function PhotoCard({
  image,
  alt,
  title,
}: (typeof stories)[number]) {
  return (
    <article className="group relative flex min-h-[280px] items-end overflow-hidden rounded-2xl bg-[#202723] sm:min-h-[360px]">
      <div
        role="img"
        aria-label={alt}
        className="absolute inset-0 bg-cover bg-center transition duration-700 group-hover:scale-105"
        style={{ backgroundImage: `url("${image}")` }}
      />
      <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/10 to-transparent" />
      <h3 className="relative p-5 text-lg font-semibold text-white sm:p-6 sm:text-xl">{title}</h3>
    </article>
  );
}

function DashboardPreview() {
  return (
    <div className="relative mx-auto w-full max-w-[570px] rounded-[26px] border border-white/10 bg-[#151a18] p-3 shadow-[0_32px_100px_rgba(0,0,0,0.42)] sm:p-5">
      <div className="flex items-center justify-between border-b border-white/10 px-2 pb-4">
        <div className="flex items-center gap-2.5">
          <Image
            src="/images/logo-white.png"
            alt="Synorra"
            width={437}
            height={366}
            sizes="86px"
            className="h-8 w-[86px] object-cover"
          />
        </div>
        <div className="flex items-center gap-2 text-[10px] text-white/45">
          <span className="h-2 w-2 rounded-full bg-[#b8f36b]" />
          STORE OVERVIEW
        </div>
      </div>

      <div className="grid gap-3 pt-4 sm:grid-cols-[1.3fr_0.7fr]">
        <div className="rounded-2xl bg-[#202723] p-4 sm:p-5">
          <div className="flex items-start justify-between">
            <div>
              <p className="text-[10px] tracking-[0.16em] text-white/45 uppercase">Sales overview</p>
              <p className="mt-2 text-2xl font-semibold tracking-tight sm:text-3xl">Your business</p>
            </div>
            <span className="rounded-full bg-white/5 px-2.5 py-1 text-[9px] text-white/55">THIS WEEK</span>
          </div>
          <div className="mt-7 flex h-24 items-end gap-2 sm:h-32">
            {[34, 52, 43, 76, 58, 91, 69, 100, 75, 85, 62, 95].map((height, index) => (
              <div key={index} className="flex-1 rounded-t-sm bg-[#b8f36b]" style={{ height: `${height}%`, opacity: 0.38 + index * 0.05 }} />
            ))}
          </div>
          <div className="mt-2 flex justify-between text-[9px] text-white/35"><span>MON</span><span>WED</span><span>FRI</span><span>SUN</span></div>
        </div>

        <div className="grid grid-cols-2 gap-3 sm:grid-cols-1">
          <div className="rounded-2xl bg-[#202723] p-4">
            <p className="text-[9px] tracking-[0.12em] text-white/45 uppercase">Sales</p>
            <div className="mt-3 h-1.5 rounded-full bg-white/10"><div className="h-full w-3/4 rounded-full bg-[#b8f36b]" /></div>
            <p className="mt-2 text-[10px] text-white/40">Track your progress</p>
          </div>
          <div className="rounded-2xl bg-[#202723] p-4">
            <p className="text-[9px] tracking-[0.12em] text-white/45 uppercase">Inventory</p>
            <div className="mt-3 flex items-center gap-2">
              <span className="h-7 w-7 rounded-lg bg-[#b8f36b]/15 text-center text-sm leading-7 text-[#b8f36b]">✓</span>
              <span className="text-[10px] text-white/65">Stock organized</span>
            </div>
          </div>
        </div>

        <div className="rounded-2xl border border-white/5 bg-[#1b211e] p-4 sm:col-span-2">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-[9px] tracking-[0.12em] text-white/45 uppercase">Built around your workflow</p>
              <p className="mt-1 text-sm font-medium">Orders · Team · Recipes</p>
            </div>
            <span className="rounded-full bg-[#b8f36b] px-3 py-1.5 text-[9px] font-bold tracking-wide text-[#111711]">SYNORRA POS</span>
          </div>
        </div>
      </div>
      <p className="mt-3 text-center text-[9px] tracking-[0.12em] text-white/30 uppercase">Product preview · Sample interface</p>
    </div>
  );
}

export function LandingPage() {
  return (
    <main className="overflow-hidden bg-[#f6f7f2] text-[#15201a]">
      <header className="mx-auto flex max-w-7xl items-center justify-between px-5 py-5 sm:px-8 sm:py-6">
        <Link href="/" aria-label="Synorra home" className="flex items-center gap-2.5">
          <Image
            src="/images/logo-transparent.png"
            alt="Synorra POS"
            width={437}
            height={366}
            priority
            sizes="132px"
            className="h-12 w-[132px] object-cover"
          />
        </Link>
        <nav className="hidden items-center gap-8 text-sm text-[#536057] md:flex">
          <a href="#features" className="transition hover:text-[#15201a]">Features</a>
          <a href="#platform" className="transition hover:text-[#15201a]">Platform</a>
        </nav>
        <Link href="/back-office" className="rounded-full bg-[#15201a] px-4 py-2.5 text-xs font-semibold text-white transition hover:bg-[#2d3b32] sm:px-5 sm:text-sm">
          Log in
        </Link>
      </header>

      <section className="relative px-5 pb-20 pt-12 sm:px-8 sm:pb-28 sm:pt-20">
        <div className="pointer-events-none absolute -right-40 -top-24 h-[520px] w-[520px] rounded-full bg-[#b8f36b]/30 blur-[100px]" />
        <div className="relative mx-auto grid max-w-7xl items-center gap-12 lg:grid-cols-[0.95fr_1.05fr] lg:gap-8">
          <div className="max-w-xl">
            <p className="inline-flex items-center gap-2 rounded-full border border-[#dce3d5] bg-white/70 px-3 py-1.5 text-[10px] font-semibold tracking-[0.14em] text-[#536057] uppercase">
              <span className="h-1.5 w-1.5 rounded-full bg-[#73b532]" />
              Point of sale, made simple
            </p>
            <h1 className="mt-6 text-[3.25rem] leading-[0.98] font-semibold tracking-[-0.065em] sm:text-7xl lg:text-[5.3rem]">
              Run your store.
              <br />
              <span className="text-[#6a9e38]">Know your business.</span>
            </h1>
            <p className="mt-6 max-w-lg text-base leading-7 text-[#657168] sm:text-lg sm:leading-8">
              Synorra brings checkout, sales, inventory, recipes, and team
              permissions into one workspace designed for café operations.
            </p>
            <div className="mt-8 flex flex-wrap items-center gap-3">
              <Link href="/back-office" className="rounded-full bg-[#15201a] px-6 py-3.5 text-sm font-semibold text-white shadow-lg shadow-[#15201a]/10 transition hover:-translate-y-0.5 hover:bg-[#2d3b32]">
                Open Synorra POS <span aria-hidden="true" className="ml-2">↗</span>
              </Link>
              <a href="#features" className="rounded-full px-5 py-3.5 text-sm font-semibold text-[#536057] transition hover:bg-white">Explore features</a>
            </div>
            <div className="mt-9 flex flex-wrap gap-x-6 gap-y-2 text-[11px] text-[#78837a]">
              <span>✓ Sales and reports</span>
              <span>✓ Inventory and restocks</span>
              <span>✓ Staff permissions</span>
            </div>
          </div>
          <div className="relative px-0 sm:px-4 lg:pl-8">
            <div className="absolute -left-4 top-8 hidden rounded-2xl border border-[#e5e9e1] bg-white px-4 py-3 shadow-xl shadow-[#15201a]/5 sm:block">
              <p className="text-[9px] tracking-[0.12em] text-[#78837a] uppercase">One workspace</p>
              <p className="mt-1 text-xs font-semibold">Sales · Stock · Team</p>
            </div>
            <DashboardPreview />
          </div>
        </div>
      </section>

      <section className="px-5 pb-16 sm:px-8 sm:pb-24">
        <div className="mx-auto grid max-w-7xl gap-4 sm:grid-cols-3">
          {stories.map((story) => <PhotoCard key={story.title} {...story} />)}
        </div>
        <p className="mx-auto mt-3 max-w-7xl text-right text-[10px] text-[#929c93]">
          Photos: Unsplash
        </p>
      </section>

      <section id="features" className="border-y border-[#e6e9e2] bg-white px-5 py-16 sm:px-8 sm:py-24">
        <div className="mx-auto max-w-7xl">
          <div className="max-w-2xl">
            <p className="text-[10px] font-semibold tracking-[0.2em] text-[#6a9e38] uppercase">Everything in sync</p>
            <h2 className="mt-4 text-3xl leading-tight font-semibold tracking-[-0.045em] sm:text-5xl">The tools you need, all in one place.</h2>
            <p className="mt-4 text-sm leading-6 text-[#657168] sm:text-base">From the first order of the day to the last stock check, keep your operation moving with a system that works together.</p>
          </div>
          <div className="mt-10 grid gap-px overflow-hidden rounded-3xl border border-[#e6e9e2] bg-[#e6e9e2] sm:grid-cols-2 lg:grid-cols-4">
            {features.map((feature) => (
              <article key={feature.number} className="bg-white p-6 sm:p-7">
                <div className="flex items-center justify-between">
                  <span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-[#eef6e7] text-xl text-[#5f8e35]">{feature.icon}</span>
                  <span className="text-[10px] tracking-[0.12em] text-[#9aa39b]">{feature.number}</span>
                </div>
                <h3 className="mt-8 text-base font-semibold tracking-tight">{feature.title}</h3>
                <p className="mt-2 text-sm leading-6 text-[#718076]">{feature.description}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section id="how-it-works" className="px-5 py-16 sm:px-8 sm:py-24">
        <div className="mx-auto grid max-w-7xl items-center gap-10 rounded-[28px] bg-[#15201a] px-6 py-10 text-white sm:px-12 sm:py-14 lg:grid-cols-[1fr_auto]">
          <div className="max-w-2xl">
            <p className="text-[10px] font-semibold tracking-[0.2em] text-[#b8f36b] uppercase">Ready when you are</p>
            <h2 className="mt-4 text-3xl leading-tight font-semibold tracking-[-0.045em] sm:text-5xl">A clearer way to run your day.</h2>
            <p className="mt-4 max-w-xl text-sm leading-6 text-white/60 sm:text-base">Sign in to your Synorra workspace and pick up right where your business needs you.</p>
          </div>
          <Link href="/back-office" className="inline-flex items-center justify-center rounded-full bg-[#b8f36b] px-6 py-3.5 text-sm font-bold text-[#15201a] transition hover:bg-[#c9fa8e]">
            Log in to Synorra <span aria-hidden="true" className="ml-2">↗</span>
          </Link>
        </div>
      </section>

      <section id="platform" className="border-t border-[#e6e9e2] bg-white px-5 py-16 sm:px-8 sm:py-20">
        <div className="mx-auto grid max-w-7xl gap-8 md:grid-cols-[0.8fr_1.2fr] md:items-end">
          <div>
            <p className="text-[10px] font-semibold tracking-[0.2em] text-[#6a9e38] uppercase">One workspace for your operation</p>
            <h2 className="mt-4 text-3xl leading-tight font-semibold tracking-[-0.045em] sm:text-4xl">Your counter and back office, connected.</h2>
          </div>
          <p className="max-w-2xl text-sm leading-7 text-[#657168] sm:text-base">
            Take orders at the POS, review sales, manage stock and restocks,
            configure recipe costing, and control staff access from one system.
            Each Owner account has its own operational workspace for its menu,
            inventory, sales, and staff.
          </p>
        </div>
      </section>

      <footer className="bg-[#15201a] px-5 py-12 text-white sm:px-8 sm:py-16">
        <div className="mx-auto grid max-w-7xl gap-10 sm:grid-cols-2 lg:grid-cols-[1.2fr_1fr_1fr_1fr]">
          <div>
            <Link href="/" className="inline-flex items-center gap-2.5 font-bold tracking-tight">
              <Image
                src="/images/logo-white.png"
                alt="Synorra POS"
                width={437}
                height={366}
                sizes="132px"
                className="h-12 w-[132px] object-cover"
              />
            </Link>
            <p className="mt-4 max-w-xs text-sm leading-6 text-white/55">A point-of-sale and operations workspace for cafés and beverage shops.</p>
          </div>
          <div>
            <p className="text-[10px] font-semibold tracking-[0.18em] text-white/40 uppercase">Point of sale</p>
            <p className="mt-4 text-sm leading-6 text-white/75">Process orders<br />Handle dine-in and takeout</p>
          </div>
          <div>
            <p className="text-[10px] font-semibold tracking-[0.18em] text-white/40 uppercase">Operations</p>
            <p className="mt-4 text-sm leading-6 text-white/75">Sales and reports<br />Inventory and recipe costing</p>
          </div>
          <div>
            <p className="text-[10px] font-semibold tracking-[0.18em] text-white/40 uppercase">Team access</p>
            <p className="mt-4 text-sm leading-6 text-white/75">Staff accounts<br />Owner-managed permissions</p>
          </div>
        </div>
        <div className="mx-auto mt-10 flex max-w-7xl flex-col gap-3 border-t border-white/10 pt-5 text-[10px] tracking-[0.12em] text-white/35 sm:flex-row sm:items-center sm:justify-between">
          <p>© {new Date().getFullYear()} Synorra POS</p>
          <p>Sales · Inventory · Team</p>
        </div>
      </footer>
    </main>
  );
}
