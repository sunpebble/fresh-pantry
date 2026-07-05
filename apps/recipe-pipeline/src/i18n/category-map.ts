import type { Category } from '../clean/schema';
import type { Lang } from './schema';

export const CATEGORY_I18N: Record<Category, Record<Lang, string>> = {
  主食: { en: 'Staples', ja: '主食', fr: 'Féculents' },
  半成品: { en: 'Semi-prepared', ja: '半調理品', fr: 'Semi-préparés' },
  早餐: { en: 'Breakfast', ja: '朝食', fr: 'Petit-déjeuner' },
  水产: { en: 'Seafood', ja: '魚介', fr: 'Fruits de mer' },
  汤羹: { en: 'Soups', ja: 'スープ', fr: 'Soupes' },
  甜品: { en: 'Desserts', ja: 'デザート', fr: 'Desserts' },
  素菜: { en: 'Vegetarian', ja: '野菜料理', fr: 'Plats végétariens' },
  荤菜: { en: 'Meat Dishes', ja: '肉料理', fr: 'Plats de viande' },
  酱料: { en: 'Sauces', ja: 'ソース・調味料', fr: 'Sauces' },
  饮品: { en: 'Drinks', ja: '飲み物', fr: 'Boissons' },
};
