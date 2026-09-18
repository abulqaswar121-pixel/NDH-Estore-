export type VendorArchetype = 'wigs_fashion' | 'marketplace' | 'grocery_food' | 'wholesale_pod' | 'cargo_logistics' | 'travel_tours' | 'freelance_services' | 'event_ticketing' | 'digital_products' | 'rentals_subscriptions'
export type SubscriptionTier = 'starter' | 'pro' | 'global_enterprise'
export type SubscriptionStatus = 'trial' | 'active' | 'past_due' | 'expired'
export type BillingCycle = 'monthly' | 'yearly'
export type UserRole = 'admin' | 'vendor' | 'customer'
export interface DesignSettings { selected_dna:'minimal_luxe'|'vibrant_retail'|'compact_grid'|'corporate_trust'|'editorial_serif'|'street_bold'|'clean_fresh'|'split_showcase'; nav_style:'centered'|'left_compact'|'floating_island'|'sidebar'; typography:string; primary_accent:string; background_accent:string; announcement_text:string; enabled_pages:string[]; homepage_order:string[]; show_newsletter:boolean; logo_shape:'circle'|'rounded'|'hexagon'; logo_text:string; logo_url:string|null }
export interface Vendor { id:string; email:string; business_name:string; shop_slug:string; whatsapp_number:string; business_category:VendorArchetype; design_settings:DesignSettings; subscription_tier:SubscriptionTier; billing_cycle:BillingCycle; subscription_status:SubscriptionStatus; trial_end_date:string; current_period_end:string; platform_fee_percentage:number; meta_pixel_id:string|null; meta_capi_token:string|null }
export interface Product { id:string; vendor_id:string; name:string; description:string; base_price:number; image_url:string; category:string; is_featured:boolean; stock_count:number; product_type:'physical'|'booking'|'service'|'digital'; weight_kg:number }
export interface ProductVariant { id:string; product_id:string; variant_name:string; variant_value:string; price_modifier:number; stock_count:number }
export interface User {id:string;email:string;full_name:string;created_at:string}
export interface UserRoleRow {id:string;user_id:string;role:UserRole}
export interface Order {id:string;vendor_id:string;customer_id:string|null;status:string;currency:'NGN'|'USD';subtotal:number;shipping_fee:number;total:number;created_at:string}
export interface OrderItem {id:string;order_id:string;product_id:string;quantity:number;unit_price:number;variant_id:string|null}
export interface Payout {id:string;vendor_id:string;amount:number;status:string;created_at:string}
export interface Review {id:string;vendor_id:string;product_id:string;customer_id:string;rating:number;body:string;created_at:string}
