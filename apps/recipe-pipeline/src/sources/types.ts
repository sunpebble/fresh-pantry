export interface RawRecipe {
  id: string;
  sourceId: string;
  sourceRef: string;
  name: string;
  sourceCategory?: string;
  sourceDifficulty?: number;
  /** 源声明的总制作时长(分钟);有则优先于 LLM 估算。 */
  sourceCookingMinutes?: number;
  description?: string;
  rawIngredients: string[];
  portionText?: string;
  steps: string[];
  rawText?: string;
  imageUrl?: string | null;
}

export interface SourceContext {
  workDir: string;
  log: (msg: string) => void;
}

export interface RecipeSource {
  id: string;
  kind: 'deterministic' | 'llm-extract';
  collect(ctx: SourceContext): AsyncIterable<RawRecipe>;
}
