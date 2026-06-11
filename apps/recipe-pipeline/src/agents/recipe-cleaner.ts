import { createAgent } from '@flue/runtime';
import { RECIPE_CLEANER_INSTRUCTIONS } from '../clean/enrich';
import { config } from '../config';

export default createAgent(() => ({
  model: config.model,
  instructions: RECIPE_CLEANER_INSTRUCTIONS,
}));
