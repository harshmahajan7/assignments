# RK Natural Tattva – Website Summary
**Malti Industries, Khargone, Madhya Pradesh**

---

## 🌐 Live Dev Server
Run with:
```bash
cd ~/Desktop/Website && npm run dev
```
Open: **http://localhost:5173**

---

## 🛍️ Pages & Features

| Page | Route | Description |
|------|-------|-------------|
| **Home** | `/` | Hero, categories, featured products, about banner, why-us, testimonials, bulk CTA |
| **Shop** | `/shop` | All 17 products, search, category filter, sort (price/rating/popular) |
| **Product Detail** | `/product/:id` | Full info, variant selector, quantity, add to cart, wishlist, related products |
| **Cart** | `/cart` | Items, quantity control, coupon (try `RKNEW10`), order summary |
| **Checkout** | `/checkout` | 3-step: Shipping → Payment (UPI/Card/NetBanking/COD) → Confirm |
| **About** | `/about` | Story, values, journey timeline, map |
| **Contact** | `/contact` | Inquiry form, bulk order, WhatsApp link, address |
| **Wishlist** | `/wishlist` | Saved products |

---

## 📦 Product Categories (17 Products)

- 🌾 **Roasted Channa** – Hing, Peri Peri, Tomato, Garlic, Classic Salt
- 🥜 **Dry Fruits** – California Almonds, Cashews W240, Medjool Dates
- 🌱 **Seeds** – Organic Chia, Flax Seeds, Pumpkin Seeds
- 🫘 **Pulses & Dal** – Chana Dal, Moong Dal
- 🌾 **Grains & Flour** – Besan, Sattu
- ⭐ **Makhana** – Classic & Peri Peri Roasted Makhana

---

## 🎨 Design System

- **Font**: Outfit (body) + Playfair Display (headings) from Google Fonts
- **Colors**: Deep green (#0F1A0F) background, Gold (#C9A84C) accents
- **Style**: Premium dark mode, glassmorphism cards, hover animations
- **Responsive**: Mobile-friendly on all screen sizes

---

## ⚙️ Technology Stack

- **React** (Vite) – Frontend
- **React Router DOM** – Client-side routing
- **React Hot Toast** – Notifications
- **Lucide React** – Icons
- **localStorage** – Cart & wishlist persistence (no backend needed for demo)

---

## 💳 Demo Coupon
Use code **`RKNEW10`** at checkout for 10% off.

---

## 📞 Contact Info (Auto-populated)
- **Address**: Bistan Road, Bhati Jin, In Front of Anaj Mandi, Khargone, MP – 451001
- **Phone / WhatsApp**: +91-8047830017
- **Proprietor**: Mr. Sourabh Mahajan

---

## 🔜 Next Steps (Production)

1. **Backend/API**: Connect to Node.js/Spring Boot for real orders and payments
2. **Payment Gateway**: Integrate Razorpay or PayU for live UPI/card payments
3. **Database**: MySQL for orders, users, product inventory
4. **Authentication**: User login/signup with JWT
5. **Admin Panel**: Product/order management dashboard
6. **Hosting**: Deploy on Vercel (frontend) + Railway/AWS (backend)
7. **SEO**: Google Search Console + sitemap.xml submission

> [!TIP]
> To build for production: `npm run build` — creates optimized files in `/dist`
