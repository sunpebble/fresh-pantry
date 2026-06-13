import { createAgent } from '@flue/runtime';
import { RECIPE_CLEANER_INSTRUCTIONS } from '../clean/enrich';
import { config } from '../config';

export default createAgent(() => ({
  model: config.model,
  thinkingLevel: config.thinkingLevel,
  instructions: RECIPE_CLEANER_INSTRUCTIONS,
}));
