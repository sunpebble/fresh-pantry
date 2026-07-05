import { describe, expect, it } from 'vitest';
import { CATEGORIES } from '../src/clean/schema';
import { CATEGORY_I18N } from '../src/i18n/category-map';
import { LANGS } from '../src/i18n/schema';

describe('CATEGORY_I18N', () => {
  it('覆盖全部分类与目标语言,无空值', () => {
    for (const category of CATEGORIES) {
      for (const lang of LANGS) {
        expect(CATEGORY_I18N[category][lang], `${category}/${lang}`).toBeTruthy();
      }
    }
  });
});
